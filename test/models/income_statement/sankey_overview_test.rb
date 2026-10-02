require "test_helper"

class IncomeStatement::SankeyOverviewTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Checking", currency: "USD", balance: 0, accountable: Depository.new)
    @date = Date.new(2024, 2, 1)
  end

  test "bounds visible categories without losing decimal amounts or detail" do
    10.times do |index|
      root = @family.categories.create!(name: "Expense #{index}")
      child = @family.categories.create!(name: "Child #{index}", parent: root)
      create_transaction(account: @account, date: @date, amount: "#{index + 1}.13".to_d, category: child)
    end
    graph = overview
    expenses = graph[:nodes].select { |node| node[:kind] == "expense" }
    assert_equal 7, expenses.size
    assert_equal "56.3", graph[:spending]
    assert_equal graph[:spending].to_d, expenses.sum { |node| node[:value].to_d }
    assert_equal 10, graph[:details].size
    assert_equal 10, graph[:details].sum { |root| root[:children].size }
    assert_nil expenses.find { |node| node[:id] == "overview_other_expense" }[:filter_value]
    assert_balanced(graph)
  end

  test "keeps refunds on their correct side and includes the deficit" do
    root = @family.categories.create!(name: "Shopping")
    child = @family.categories.create!(name: "Refund", parent: root)
    create_transaction(account: @account, date: @date, amount: 100, category: root)
    create_transaction(account: @account, date: @date, amount: -30, category: child)
    graph = overview
    assert_equal "100.0", graph[:spending]
    assert_equal "30.0", graph[:income]
    assert_equal "70.0", graph[:nodes].find { |node| node[:kind] == "deficit" }[:value]
    assert_equal child.filter_value, graph[:details].find { |node| node[:kind] == "income" }[:children].first[:filter_value]
    assert_balanced(graph)
  end

  test "groups income and preserves surplus and source data" do
    5.times do |index|
      category = @family.categories.create!(name: "Income #{index}")
      create_transaction(account: @account, date: @date, amount: -10, category: category)
    end
    original = detailed_graph
    snapshot = original.deep_dup
    graph = IncomeStatement::SankeyOverview.new(original).as_json
    assert_equal snapshot, original
    assert_equal 4, graph[:nodes].count { |node| node[:kind] == "income" }
    assert_equal "50.0", graph[:nodes].find { |node| node[:kind] == "surplus" }[:value]
    assert_balanced(graph)
  end

  test "empty periods keep an empty graph" do
    assert_empty overview[:nodes]
    assert_empty overview[:links]
    assert_empty overview[:details]
  end

  private
    def detailed_graph
      IncomeStatement::Sankey.new(IncomeStatement.new(@family), period: Period.custom(start_date: @date, end_date: @date.end_of_month)).as_json
    end

    def overview
      IncomeStatement::SankeyOverview.new(detailed_graph).as_json
    end

    def assert_balanced(graph)
      incoming = graph[:links].select { |link| link[:target] == 0 }.sum { |link| link[:value].to_d }
      outgoing = graph[:links].select { |link| link[:source] == 0 }.sum { |link| link[:value].to_d }
      assert_equal incoming, outgoing
      assert_equal graph[:nodes].first[:value].to_d, incoming
    end
end
