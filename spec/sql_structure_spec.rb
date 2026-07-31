# frozen_string_literal: true

require_relative 'spec_helper'

# Structural properties of the generated SQL, checked for every filter and every
# operator it offers. These are the things a result-oriented test cannot see: an
# alias that was renamed in one builder and not another, a parenthesis that closes
# in the wrong place, a fragment that happens to execute but means something else.
#
# Deliberately not a snapshot of the whole statement. A snapshot would have to be
# rewritten on every Redmine release, for no gain: what matters is that the shape
# holds, not that the bytes are what they were.
RSpec.describe 'the shape of the generated SQL' do
  # Aliases the plugin introduces, plus the ones Redmine introduces itself. Any
  # other alias on the issues or projects table means a builder invented a name
  # nothing else knows about.
  # solo, tparent and tchild belong to the structural filters: "has no relatives"
  # and "has a parent or a child" are answered by testing for a *visible* relative,
  # which needs an alias of its own on each side.
  KNOWN_ISSUE_ALIASES = (
    %w[parent child ancestor descendant root tree subtasks ct
       solo tparent tchild] +
    (1..RedmineParentChildFilters::MAX_DEPTH).map { |i| "parent#{i}" }
  ).freeze

  KNOWN_PROJECT_ALIASES = (
    %w[parent child ancestor descendant root tree
       solo tparent tchild] +
    (1..RedmineParentChildFilters::MAX_DEPTH).map { |i| "parent#{i}" }
  ).map { |name| "#{name}_projects" }.freeze

  def plugin_filters
    previous = Setting.plugin_redmine_parent_child_filters
    all_off = previous.keys.grep(/\Aenable_/).to_h { |key| [key, '0'] }
    Setting.plugin_redmine_parent_child_filters = previous.merge(all_off)
    without = IssueQuery.new.available_filters.keys
    Setting.plugin_redmine_parent_child_filters = previous
    IssueQuery.new.available_filters.keys - without
  end

  def sample_value(field, operator)
    return [''] if %w[o c * !*].include?(operator)

    case field
    when 'root_id' then [Issue.first.id.to_s]
    when /\Aa_specific_parent_tracker/ then ["#{Tracker.first.id}:1"]
    when /\Aa_specific_parent_status/ then ["#{IssueStatus.first.id}:1"]
    when /involved|mentioned/ then [User.find(2).id.to_s]
    when /tracker_id\z/ then [Tracker.first.id.to_s]
    when /status_id\z/ then [IssueStatus.first.id.to_s]
    else ['1']
    end
  end

  def each_filter_and_operator
    query_for_operators = IssueQuery.new(:name => '_')

    plugin_filters.each do |field|
      operators = Query.operators_by_filter_type[query_for_operators.available_filters[field][:type]]
      operators.each do |operator|
        query = unfiltered_query
        query.add_filter(field, operator, sample_value(field, operator))
        next unless query.valid?

        yield field, operator, query.statement
      end
    end
  end

  it 'balances its parentheses, for every filter and operator' do
    unbalanced = []

    each_filter_and_operator do |field, operator, statement|
      depth = 0
      # Quoted strings may hold a stray parenthesis, so they are removed first.
      statement.gsub(/'[^']*'/, "''").each_char do |char|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        break if depth.negative?
      end
      unbalanced << "#{field} #{operator}" unless depth.zero?
    end

    expect(unbalanced).to eq([])
  end

  # A table can appear unaliased, in which case the next word is SQL rather than a
  # name. Those are not aliases and must not be read as one.
  SQL_KEYWORDS = %w[on inner left right outer join where group order union and or
                    having limit offset as select from].freeze

  def aliases_of(statement, table)
    statement
      .scan(/(?:FROM|JOIN)\s+#{table}\s+(?:AS\s+)?(\w+)/i).flatten
      .reject { |name| SQL_KEYWORDS.include?(name.downcase) }
  end

  it 'introduces no alias the rest of the plugin does not know' do
    strays = []

    each_filter_and_operator do |field, operator, statement|
      (aliases_of(statement, Issue.table_name) - KNOWN_ISSUE_ALIASES)
        .each { |a| strays << "#{field} #{operator}: issues #{a}" }
      (aliases_of(statement, Project.table_name) - KNOWN_PROJECT_ALIASES)
        .each { |a| strays << "#{field} #{operator}: projects #{a}" }
    end

    expect(strays).to eq([])
  end

  # Every alias that carries a condition has to be joined to its project, or the
  # visibility condition would silently read the outer query's project instead —
  # which is the bug Redmine core has in its own total_estimated_hours column.
  it 'joins projects for every alias whose visibility it tests' do
    missing = []

    each_filter_and_operator do |field, operator, statement|
      statement.scan(/(\w+)_projects\./).flatten.uniq.each do |alias_name|
        joined = statement.include?("#{Project.table_name} #{alias_name}_projects")
        missing << "#{field} #{operator}: #{alias_name}_projects used but not joined" unless joined
      end
    end

    expect(missing).to eq([])
  end

  it 'leaves no empty condition, doubled operator or dangling AND' do
    broken = []

    each_filter_and_operator do |field, operator, statement|
      squished = statement.squeeze(' ')
      broken << "#{field} #{operator}: AND AND" if squished.include?(' AND AND ')
      broken << "#{field} #{operator}: AND )" if squished.match?(/AND\s*\)/)
      broken << "#{field} #{operator}: ( AND" if squished.match?(/\(\s*AND/)
      broken << "#{field} #{operator}: empty ()" if squished.include?('()')
    end

    expect(broken).to eq([])
  end

  # The point of all of the above: it executes, and the enumeration really did
  # visit every combination rather than quietly skipping them.
  #
  # The expected number is computed from the same data instead of written down,
  # because the operator lists differ per Redmine version — 5.0 has no history
  # operators, so a fixed number would either be wrong there or too weak here.
  it 'executes for every filter and operator' do
    failures = []
    visited = []

    each_filter_and_operator do |field, operator, _statement|
      query = unfiltered_query
      query.add_filter(field, operator, sample_value(field, operator))
      visited << "#{field} #{operator}"
      begin
        query.issue_count
      rescue StandardError => e
        failures << "#{field} #{operator}: #{e.class}: #{e.message.lines.first.strip}"
      end
    end

    reference = IssueQuery.new(:name => '_')
    expected = plugin_filters.flat_map do |field|
      operators = Query.operators_by_filter_type[reference.available_filters[field][:type]]
      operators.map { |operator| "#{field} #{operator}" }
    end

    expect(failures).to eq([])
    expect(visited.sort).to eq(expected.sort)
  end
end
