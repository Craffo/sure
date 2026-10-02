require "test_helper"

class IncomeStatement::SankeyTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Checking", currency: "USD", balance: 0, accountable: Depository.new)
    @month = Date.new(2024, 2, 1)
    @parent = @family.categories.create!(name: "Shopping", color: "#123456")
    @child = @family.categories.create!(name: "Rebates", parent: @parent)
  end

  test "opposite direction children are not double counted in parent totals" do
    transaction(100, @parent)
    transaction(-30, @child)
    result = graph
    assert_equal "100.0", result[:spending]
    assert_equal "30.0", result[:income]
    assert_equal "-70.0", result[:net_savings]
    assert_equal "100.0", node(result, "expense_#{@parent.id}")[:value]
    assert_equal "30.0", node(result, "income_#{@parent.id}")[:value]
    assert_equal @child.filter_value, node(result, "income_sub_#{@child.id}")[:filter_value]
    assert_equal "70.0", node(result, "deficit_node")[:value]
    assert_balanced(result)
  end

  test "zero net parent retains both directions and same-category refunds net once" do
    transaction(150, @parent)
    transaction(-50, @parent)
    transaction(-100, @child)
    result = graph
    assert_equal "100.0", result[:income]
    assert_equal "100.0", result[:spending]
    assert_equal "0.0", result[:net_savings]
    assert_balanced(result)
  end

  test "same direction children share parent capacity without duplicating totals" do
    transaction(10, @parent)
    transaction(20, @child)
    result = graph
    assert_equal "30.0", result[:spending]
    assert_equal "30.0", node(result, "expense_#{@parent.id}")[:value]
    assert_equal "20.0", node(result, "expense_sub_#{@child.id}")[:value]
    assert_balanced(result)
  end

  test "decimal netting retains sub-cent precision beyond floating point accuracy" do
    transaction("900719925474.1234".to_d, @parent)
    transaction("-900719925474.1233".to_d, @parent)
    transaction("0.2".to_d, @child)
    result = graph
    assert_equal "0.2001", result[:spending]
    assert_equal "0.2001", node(result, "expense_#{@parent.id}")[:value]
    assert_equal "0.2", node(result, "expense_sub_#{@child.id}")[:value]
    assert_equal "0.2001", node(result, "deficit_node")[:value]
    assert_balanced(result)
  end

  test "a spending-only period has an explicit deficit through cash flow to expenses" do
    transaction(160, @parent)
    result = graph
    assert_equal "0.0", result[:income]
    assert_equal "160.0", result[:spending]
    assert_equal "-160.0", result[:net_savings]
    assert_equal [
      [ "cash_flow_node", "expense_#{@parent.id}", "160.0" ],
      [ "deficit_node", "cash_flow_node", "160.0" ]
    ].sort, result[:links].map { |link| [ result[:nodes][link[:source]][:id], result[:nodes][link[:target]][:id], link[:value] ] }.sort
    assert_balanced(result)
  end

  test "preserves FX precision, reporting eligibility and surplus" do
    eur = @family.accounts.create!(name: "EUR", currency: "EUR", balance: 0, accountable: Depository.new)
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: @month, rate: "1.2345")
    create_transaction(account: eur, currency: "EUR", amount: 10, date: @month, category: @child)
    transaction(-100, @parent)
    create_transaction(account: @account, amount: 900, date: @month, excluded: true)
    create_transaction(account: @account, amount: 800, date: @month, kind: "cc_payment")
    pending = create_transaction(account: @account, amount: 700, date: @month)
    pending.entryable.update!(extra: { "simplefin" => { "pending" => true } })
    create_transaction(account: accounts(:depository), amount: 600, date: @month)
    result = graph
    assert_equal "12.345", result[:spending]
    assert_equal "87.655", node(result, "surplus_node")[:value]
    assert_balanced(result)
  end

  test "empty graph and uncategorized identifiers are deterministic" do
    assert_empty graph[:nodes]
    assert_empty graph[:links]
    transaction(10, nil)
    assert_equal "10.0", node(graph, "expense_uncategorized")[:value]
    assert_equal graph, graph
  end

  test "borrowing funds cash flow once without becoming budget income and repayments remain outflows" do
    transaction(-2000, @parent)
    create_transaction(account: @account, date: @month, amount: -15000, kind: "loan_disbursement", category: @parent)
    create_transaction(account: @account, date: @month, amount: 667.99, kind: "loan_payment", category: @child)
    create_transaction(account: @account, date: @month, amount: -500, kind: "funds_movement")
    create_transaction(account: @account, date: @month, amount: 500, kind: "funds_movement")
    result = graph
    assert_equal "17000.0", result[:income]
    assert_equal "15000.0", result[:financing_income]
    assert_equal "667.99", result[:spending]
    assert_equal "16332.01", result[:net_savings]
    assert_equal "15000.0", node(result, "financing_inflow")[:value]
    budget = IncomeStatement.new(@family).totals(date_range: @month..@month.end_of_month)
    assert_equal 2000, budget.income_money.amount
    assert_equal 667.99.to_d, budget.expense_money.amount
    assert_balanced(result)
  end

  test "financing respects dates, pending status, exclusion, family, account selection and exchange rates" do
    eur = @family.accounts.create!(name: "EUR", currency: "EUR", balance: 0, accountable: Depository.new)
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: @month, rate: "1.2345")
    create_transaction(account: eur, currency: "EUR", date: @month, amount: -100, kind: "loan_disbursement")
    create_transaction(account: @account, date: @month, amount: -700, kind: "loan_disbursement", excluded: true)
    create_transaction(account: @account, date: @month - 1.day, amount: -800, kind: "loan_disbursement")
    pending = create_transaction(account: @account, date: @month, amount: -900, kind: "loan_disbursement")
    pending.entryable.update!(extra: { "enable_banking" => { "pending" => true } })
    create_transaction(account: accounts(:depository), date: @month, amount: -1000, kind: "loan_disbursement")
    assert_equal "123.45", graph[:income]
    assert_balanced(graph)
    period = Period.custom(start_date: @month, end_date: @month.end_of_month)
    assert_equal 0, IncomeStatement.new(@family, accounts: [ @account ]).financing_inflows(period: period)
    assert_equal 0, IncomeStatement.new(@family, accounts: []).financing_inflows(period: period)
    eur.update!(exclude_from_reports: true)
    assert_equal "0.0", graph[:income]
  end

  private
    def transaction(amount, category)
      create_transaction(account: @account, amount: amount, category: category, date: @month)
    end

    def graph
      IncomeStatement::Sankey.new(IncomeStatement.new(@family), period: Period.custom(start_date: @month, end_date: @month.end_of_month)).as_json
    end

    def node(graph, id)
      graph[:nodes].find { |node| node[:id] == id }
    end

    def assert_balanced(graph)
      center = graph[:nodes].index { |node| node[:id] == "cash_flow_node" }
      incoming = graph[:links].select { |link| link[:target] == center }.sum { |link| link[:value].to_d }
      outgoing = graph[:links].select { |link| link[:source] == center }.sum { |link| link[:value].to_d }
      assert_equal incoming, outgoing
      graph[:nodes].each_with_index do |node, index|
        allocations = %i[source target].map do |end_point|
          graph[:links].select { |link| link[end_point] == index }.sum { |link| link[:value].to_d }
        end
        assert_operator node[:value].to_d, :>, 0
        assert_equal node[:value].to_d, allocations.max, "#{node[:id]} must match its links' capacity"
      end
    end
end
