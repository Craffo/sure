module CashflowOverviewHelper
  # Convert decimal amounts only at the geometry boundary, never for totals.
  def cashflow_overview_chart_data(data)
    {
      nodes: data[:nodes].map do |node|
        fallback = %w[expense deficit].include?(node[:kind]) ? "var(--color-destructive)" : "var(--color-success)"
        node.merge(value: node[:value].to_f, percentage: node[:percentage].to_f, color: node[:color].presence || fallback)
      end,
      links: data[:links].map { |link| link.merge(value: link[:value].to_f, percentage: link[:percentage].to_f) }
    }
  end

  def cashflow_overview_category_path(node, period)
    transactions_path(q: { categories: [ node[:filter_value] ], start_date: period.start_date, end_date: period.end_date })
  end

  def cashflow_overview_detail_rows(data, side)
    data[:details].select { |root| root[:kind] == side }.flat_map do |root|
      [ root ] + root[:children].map { |child| child.merge(sub: true) }
    end
  end
end
