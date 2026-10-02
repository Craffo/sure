# A bounded overview of the existing, balanced cash-flow graph. Aggregation is
# presentation-only: category IDs, refunds and report eligibility stay upstream.
class IncomeStatement::SankeyOverview
  LIMITS = { "income" => 3, "expense" => 6 }.freeze

  def initialize(graph)
    @graph = graph
  end

  def as_json(*)
    return @graph.merge(details: []) if @graph[:links].empty?

    center_index = @graph[:nodes].index { |node| node[:kind] == "cash_flow" }
    nodes = [ @graph[:nodes].fetch(center_index).dup ]
    links = []
    details = []

    LIMITS.each do |side, limit|
      roots = @graph[:links].filter_map do |link|
        index = if side == "income" && link[:target] == center_index
          link[:source]
        elsif side == "expense" && link[:source] == center_index
          link[:target]
        end
        node = @graph[:nodes][index] if index
        node if node && node[:kind] == side
      end.sort_by { |node| [ -node[:value].to_d, node[:id] ] }

      details.concat(roots.map { |root| detail(root, side) })
      financing, categories = roots.partition { |node| node[:financing] }
      category_limit = [ limit - financing.size, 0 ].max
      visible = (financing + categories.first(category_limit)).map(&:dup)
      remainder = categories.drop(category_limit)
      if remainder.any?
        value = remainder.sum { |node| node[:value].to_d }
        total = roots.sum { |node| node[:value].to_d }
        visible << { id: "overview_other_#{side}", kind: side,
          name: I18n.t("pages.dashboard.cashflow_overview.other_#{side}"),
          value: value.to_s("F"), percentage: (value / total * 100).round(1).to_s("F"),
          color: "var(--color-gray-400)", category_id: nil, filter_value: nil }
      end
      visible.each { |node| append(nodes, links, node, incoming: side == "income") }
    end

    @graph[:nodes].select { |node| %w[surplus deficit].include?(node[:kind]) }.each do |node|
      append(nodes, links, node.dup, incoming: node[:kind] == "deficit")
    end
    @graph.merge(nodes: nodes, links: links, details: details)
  end

  private
    def append(nodes, links, node, incoming:)
      index = nodes.length
      nodes << node
      links << { source: incoming ? index : 0, target: incoming ? 0 : index,
                 value: node[:value], percentage: node[:percentage] }
    end

    def detail(root, side)
      index = @graph[:nodes].index(root)
      children = @graph[:links].filter_map do |link|
        child_index = if side == "expense" && link[:source] == index
          link[:target]
        elsif side == "income" && link[:target] == index
          link[:source]
        end
        @graph[:nodes][child_index] if child_index
      end.sort_by { |node| -node[:value].to_d }
      root.merge(children: children)
    end
end
