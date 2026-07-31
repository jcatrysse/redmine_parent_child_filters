# frozen_string_literal: true

require_dependency 'issue_query'
require File.expand_path('filter_registration', __dir__)
require File.expand_path('value_parsing', __dir__)
require File.expand_path('visibility_scope', __dir__)

# Every filter this plugin adds is built from two pieces:
#
#   * a condition on a related issue, written against a SQL alias
#     (pcf_tracker_condition / pcf_status_condition), and
#   * a quantifier over the set of related issues, positive for "is" and
#     negative for "is not" (pcf_*_condition).
#
# Keeping those two apart is what makes the filters read the same way in every
# direction: "is not" always means "there is no such relative", and a tracker
# filter combined with a status filter always describes the same relative.
module RedmineParentChildFilters
  module Patches
    module IssueQueryPatch
      module InstanceMethods
        include FilterRegistration
        include ValueParsing
        include VisibilityScope

        # Tracker and status filters that range over a set of relatives, and so
        # have to agree on which relative they are talking about.
        PAIRED_FILTERS = [
          %w[a_parent_tracker_id a_parent_status_id],
          %w[child_tracker_id child_status_id],
          %w[a_child_tracker_id a_child_status_id],
          %w[tree_tracker_id tree_status_id],
          %w[tree_parent_tracker_id tree_parent_status_id],
          %w[tree_child_tracker_id tree_child_status_id]
        ].freeze

        # Filters that name a tracker, in registration order.
        TRACKER_FILTERS = %w[
          root_tracker_id parent_tracker_id a_parent_tracker_id
          child_tracker_id a_child_tracker_id
          tree_tracker_id tree_parent_tracker_id tree_child_tracker_id
        ].freeze

        # Filters that name a status, in registration order.
        STATUS_FILTERS = %w[
          root_status_id parent_status_id a_parent_status_id
          child_status_id a_child_status_id
          tree_status_id tree_parent_status_id tree_child_status_id
        ].freeze

        # The order the filters appear in, so that the dropdown groups the
        # hierarchy the way the sidebar does: root first, then up, then down,
        # then the whole tree.
        FILTER_ORDER = %w[
          root_id root_tracker_id root_status_id
          parent_tracker_id parent_status_id
          a_parent_tracker_id a_parent_status_id
          a_specific_parent_tracker_id a_specific_parent_status_id
          child_tracker_id child_status_id
          a_child_tracker_id a_child_status_id
          tree_has_parent_or_child
          tree_tracker_id tree_status_id
          tree_parent_tracker_id tree_parent_status_id
          tree_child_tracker_id tree_child_status_id
        ].freeze

        def initialize_available_filters
          super

          FILTER_ORDER.each { |name| pcf_register_filter(name, pcf_filter_options(name)) }
        end

        def pcf_filter_options(name)
          case name
          when 'root_id'
            {:type => :tree}
          when 'tree_has_parent_or_child'
            {:type => :list,
             :values => [[l(:general_text_yes), '1'], [l(:general_text_no), '0']]}
          when 'a_specific_parent_tracker_id'
            {:type => :list, :values => lambda { pcf_depth_values(pcf_tracker_values) }}
          when 'a_specific_parent_status_id'
            {:type => :list, :values => lambda { pcf_depth_values(issue_statuses_values) }}
          when *TRACKER_FILTERS
            {:type => :list, :values => lambda { pcf_tracker_values }}
          when *STATUS_FILTERS
            {:type => :list_status, :values => lambda { issue_statuses_values }}
          else
            raise "unknown filter #{name}"
          end
        end

        def pcf_tracker_values
          trackers.collect { |tracker| [tracker.name, tracker.id.to_s] }
        end

        # "(2) Feature" means "the tracker of the grandparent is Feature". The
        # depth is carried in the value because Redmine gives a filter one value
        # list, not two.
        def pcf_depth_values(pairs)
          depths = RedmineParentChildFilters.depth_range

          pairs.flat_map do |label, id|
            depths.map { |depth| ["(#{depth}) #{label}", "#{id}:#{depth}"] }
          end
        end

        def sql_for_root_id_field(field, operator, value)
          case operator
          when "=", "~"
            # accepts a comma separated list of ids
            ids = pcf_id_list(value.first)
            ids ? "#{Issue.table_name}.root_id IN (#{ids})" : "1=0"
          when "*"
            # Every issue belongs to a tree, its own if it has no relatives, so
            # "any root" is every issue and "no root" is none. Stated explicitly
            # rather than relying on root_id being populated.
            "1=1"
          when "!*"
            "1=0"
          end
        end

        # The root of an issue without relatives is the issue itself, so both
        # the issue and its root are tested.
        def sql_for_root_tracker_id_field(field, operator, value)
          return pcf_always_present_condition(operator) if pcf_existence_only?(operator)

          return '' unless %w[= !].include?(operator)

          own = pcf_tracker_condition(value, Issue.table_name)
          return pcf_no_value_condition(operator) if own.nil?

          pcf_root_condition(own, pcf_tracker_condition(value, 'root'), operator)
        end

        def sql_for_root_status_id_field(field, operator, value)
          # Until 1.0.0 "any status" here meant "is not its own root", which is a
          # different question — "has a parent" — and made this filter disagree
          # with root_id and root_tracker_id about what "any" means. Redmine
          # answers that question itself, with Parent task: any.
          return pcf_always_present_condition(operator) if pcf_existence_only?(operator)

          own = pcf_status_condition(operator, value, Issue.table_name)
          return pcf_no_value_condition(operator) if own.nil? && pcf_needs_value?(operator)
          return if own.nil?

          pcf_root_condition(own, pcf_status_condition(operator, value, 'root'), operator)
        end

        def sql_for_parent_tracker_id_field(field, operator, value)
          return pcf_parent_condition(nil, operator) if pcf_existence_only?(operator)

          condition = pcf_tracker_condition(value, 'parent')
          return pcf_no_value_condition(operator) if condition.nil?

          pcf_parent_condition(condition, operator)
        end

        def sql_for_parent_status_id_field(field, operator, value)
          return pcf_parent_condition(nil, operator) if pcf_existence_only?(operator)

          condition = pcf_status_condition(operator, value, 'parent')
          return pcf_no_value_condition(operator) if condition.nil? && pcf_needs_value?(operator)
          return if condition.nil?

          pcf_parent_condition(condition, operator)
        end

        def sql_for_a_parent_tracker_id_field(field, operator, value)
          return pcf_ancestor_condition(nil, operator) if pcf_existence_only?(operator)

          condition = pcf_paired_condition('a_parent_tracker_id', value, 'ancestor')
          return pcf_no_value_condition(operator) if condition.nil?

          pcf_ancestor_condition(condition, operator)
        end

        def sql_for_a_parent_status_id_field(field, operator, value)
          return pcf_ancestor_condition(nil, operator) if pcf_existence_only?(operator)

          return '' if pcf_merged_away?('a_parent_status_id')

          condition = pcf_status_condition(operator, value, 'ancestor')
          return pcf_no_value_condition(operator) if condition.nil? && pcf_needs_value?(operator)
          return if condition.nil?

          pcf_ancestor_condition(condition, operator)
        end

        # An issue has exactly one ancestor at a given depth, so the tracker and
        # the status filter already describe the same ancestor whenever they use
        # the same depth, and different ancestors when they do not.
        def sql_for_a_specific_parent_tracker_id_field(field, operator, value)
          return pcf_ancestor_condition(nil, operator) if pcf_existence_only?(operator)

          pcf_specific_parent_sql(value, operator, 'tracker_id')
        end

        def sql_for_a_specific_parent_status_id_field(field, operator, value)
          return pcf_ancestor_condition(nil, operator) if pcf_existence_only?(operator)

          pcf_specific_parent_sql(value, operator, 'status_id')
        end

        def sql_for_child_tracker_id_field(field, operator, value)
          return pcf_child_condition(nil, operator) if pcf_existence_only?(operator)

          condition = pcf_paired_condition('child_tracker_id', value, 'child')
          return pcf_no_value_condition(operator) if condition.nil?

          pcf_child_condition(condition, operator)
        end

        def sql_for_child_status_id_field(field, operator, value)
          return pcf_child_condition(nil, operator) if pcf_existence_only?(operator)

          return '' if pcf_merged_away?('child_status_id')

          condition = pcf_status_condition(operator, value, 'child')
          return pcf_no_value_condition(operator) if condition.nil? && pcf_needs_value?(operator)

          pcf_child_condition(condition, operator)
        end

        def sql_for_a_child_tracker_id_field(field, operator, value)
          return pcf_descendant_condition(nil, operator) if pcf_existence_only?(operator)

          condition = pcf_paired_condition('a_child_tracker_id', value, 'descendant')
          return pcf_no_value_condition(operator) if condition.nil?

          pcf_descendant_condition(condition, operator)
        end

        def sql_for_a_child_status_id_field(field, operator, value)
          return pcf_descendant_condition(nil, operator) if pcf_existence_only?(operator)

          return '' if pcf_merged_away?('a_child_status_id')

          condition = pcf_status_condition(operator, value, 'descendant')
          return pcf_no_value_condition(operator) if condition.nil? && pcf_needs_value?(operator)
          return if condition.nil?

          pcf_descendant_condition(condition, operator)
        end

        def sql_for_tree_has_parent_or_child_field(field, operator, value)
          return pcf_always_present_condition(operator) if pcf_existence_only?(operator)

          positive = pcf_parse_flag(value)
          return pcf_no_value_condition(operator) if positive.nil?

          tree_condition(pcf_visible_link_subquery, operator, positive)
        end

        def sql_for_tree_tracker_id_field(field, operator, value)
          return pcf_always_present_condition(operator) if pcf_existence_only?(operator)

          condition = pcf_paired_condition('tree_tracker_id', value, 'tree')
          return pcf_no_value_condition(operator) if condition.nil?

          tree_condition(pcf_tree_subquery(condition), operator)
        end

        def sql_for_tree_status_id_field(field, operator, value)
          return pcf_always_present_condition(operator) if pcf_existence_only?(operator)

          return '' if pcf_merged_away?('tree_status_id')

          condition = pcf_status_condition(operator, value, 'tree')
          return pcf_no_value_condition(operator) if condition.nil? && pcf_needs_value?(operator)
          return if condition.nil?

          tree_condition(pcf_tree_subquery(condition), operator)
        end

        def sql_for_tree_parent_tracker_id_field(field, operator, value)
          return pcf_linked_tree_condition(operator) if pcf_existence_only?(operator)

          builder = pcf_paired_builder('tree_parent_tracker_id', value)
          return pcf_no_value_condition(operator) if builder.nil?

          tree_condition(pcf_tree_parent_subquery(builder), operator)
        end

        def sql_for_tree_parent_status_id_field(field, operator, value)
          return pcf_linked_tree_condition(operator) if pcf_existence_only?(operator)

          return '' if pcf_merged_away?('tree_parent_status_id')

          builder = pcf_status_builder(operator, value)
          return pcf_no_value_condition(operator) if builder.nil? && pcf_needs_value?(operator)
          return if builder.nil?

          tree_condition(pcf_tree_parent_subquery(builder), operator)
        end

        def sql_for_tree_child_tracker_id_field(field, operator, value)
          return pcf_linked_tree_condition(operator) if pcf_existence_only?(operator)

          builder = pcf_paired_builder('tree_child_tracker_id', value)
          return pcf_no_value_condition(operator) if builder.nil?

          tree_condition(pcf_tree_child_subquery(builder), operator)
        end

        def sql_for_tree_child_status_id_field(field, operator, value)
          return pcf_linked_tree_condition(operator) if pcf_existence_only?(operator)

          return '' if pcf_merged_away?('tree_child_status_id')

          builder = pcf_status_builder(operator, value)
          return pcf_no_value_condition(operator) if builder.nil? && pcf_needs_value?(operator)
          return if builder.nil?

          tree_condition(pcf_tree_child_subquery(builder), operator)
        end

        # Walking a parent chain N levels up is N joins, and with the visibility
        # scoping it is 2N tables. MySQL's optimiser searches join orders
        # exhaustively up to optimizer_search_depth, which defaults to 62, so past
        # about twelve tables the *planning* cost explodes factorially — measured
        # on empty fixture tables, MySQL 8 took 0.25s at eight tables, 12.75s at
        # twelve and never returned at fourteen, while PostgreSQL and MariaDB
        # planned all of them in milliseconds.
        #
        # There is nothing for the optimiser to discover here: the chain has one
        # sensible order and it is the order it is written in. STRAIGHT_JOIN says
        # so, which turns depth 10 from "never returns" into 0.01s. It is scoped to
        # this one subquery, so no other part of the query is affected.
        def pcf_join_order_hint
          Redmine::Database.mysql? ? 'STRAIGHT_JOIN ' : ''
        end

        # Trees that hold at least one parent-child link. A tree that holds a
        # parent holds a child by definition, so both the tree_parent and the
        # tree_child filters mean this same set when asked for "any".
        # Trees that hold a parent/child relationship this user can see.
        #
        # A tree holds such a relationship exactly when it holds a parent/child pair
        # with both ends visible: an issue with a visible parent is the child of such
        # a pair, one with a visible child is the parent of one, and either way the
        # pair shares its root_id. That makes it one join rather than a visible-parent
        # and a visible-child test per row — the same answer for a sixth of the cost,
        # measured on 20 000 issues against MySQL.
        #
        # One method for the two callers on purpose. They drifted apart once: the
        # "has a parent or a child" filter was scoped and this one, which answers
        # "any" and "none" for the four tree parent/child filters, was left asking
        # `linked.parent_id IS NOT NULL` — true of an issue whose parent sits in a
        # project the user cannot open. Two builders for one question is how that
        # happens.
        def pcf_visible_link_subquery
          "SELECT DISTINCT child.root_id FROM #{Issue.table_name} child" \
            " #{pcf_visible_join('child')}" \
            " INNER JOIN #{Issue.table_name} parent ON child.parent_id = parent.id" \
            " #{pcf_visible_join('parent')}" \
            " WHERE child.root_id IS NOT NULL AND #{pcf_visible_condition('child')}" \
            " AND #{pcf_visible_condition('parent')}"
        end

        def pcf_linked_tree_condition(operator)
          tree_condition(pcf_visible_link_subquery, operator)
        end

        def tree_condition(subquery, operator, positive = true)
          positive = !positive if pcf_negated?(operator)
          positive ? "#{Issue.table_name}.root_id IN (#{subquery})" : "#{Issue.table_name}.root_id NOT IN (#{subquery})"
        end

        private

        # "is not", "has never been" and "none" all ask for the absence of a
        # matching relative; every other operator asks for the presence of one.
        def pcf_negated?(operator)
          operator.to_s.start_with?('!')
        end

        def pcf_needs_value?(operator)
          %w[= ! ev !ev cf].include?(operator.to_s)
        end

        # "any" and "none" ask whether the relative exists at all, so they carry no
        # value and the condition on the relative is simply absent. Redmine offers
        # both on every list filter, so every filter here has to mean something by
        # them; they used to fall through to "no usable value", which made "any"
        # and "none" answer identically.
        def pcf_existence_only?(operator)
          %w[* !*].include?(operator.to_s)
        end

        # For a set that is never empty — every issue has a root, and belongs to a
        # tree — "any" is every issue and "none" is none.
        def pcf_always_present_condition(operator)
          pcf_negated?(operator) ? '1=0' : '1=1'
        end

        # Filter values come straight from the request, so they are never
        # interpolated as-is. Returns a comma separated list of integers, or nil
        # when the values hold no usable id.
        def pcf_history_operators_supported?
          Query.operators_by_filter_type[:list_status].include?('ev')
        end

        def pcf_max_depth
          RedmineParentChildFilters.depth_range.last
        end

        def pcf_filter_enabled?(key)
          RedmineParentChildFilters.filter_enabled?(key)
        end

        def pcf_tracker_condition(values, table)
          ids = pcf_id_list(values)
          ids && "#{table}.tracker_id IN (#{ids})"
        end

        # Condition on the status of a related row. nil means "no restriction".
        def pcf_status_condition(operator, values, table)
          case operator
          when '=', '!'
            ids = pcf_id_list(values)
            ids && "#{table}.status_id IN (#{ids})"
          when 'o'
            "#{table}.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{self.class.connection.quoted_false})"
          when 'c'
            "#{table}.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{self.class.connection.quoted_true})"
          when 'ev', '!ev', 'cf'
            # Redmine builds the journal lookup correlated on <table>.id and
            # already excludes journals the user may not read, so it can be
            # reused as-is for a related issue. "has never been" is expressed by
            # the quantifier, like every other negation here.
            #
            # Redmine 5.0 has no history operators at all: sql_for_field raises
            # QueryError for them. A value can still arrive from a hand written
            # url, so the condition is dropped rather than raised.
            return unless pcf_history_operators_supported?
            return if Array(values).reject(&:blank?).empty?

            "(#{sql_for_field('status_id', operator.delete_prefix('!'), Array(values), table, 'status_id')})"
          end
        end

        # A tracker filter and a status filter over the same set of relatives
        # describe the same relative when both ask for a match. As soon as one of
        # them asks for the absence of a match, folding them together would be
        # ambiguous ("no relative that is both" or "none at all with this
        # status"?), so each filter states its own condition and Redmine combines
        # them with AND.
        def pcf_merge_pair?(tracker_field, status_field)
          return false unless filters&.key?(tracker_field) && filters.key?(status_field)

          operator_for(tracker_field) == '=' && !pcf_negated?(filters[status_field][:operator])
        end

        # Condition for a tracker filter, with the paired status folded in when
        # the two describe the same relative.
        def pcf_paired_condition(tracker_field, values, table)
          pcf_paired_builder(tracker_field, values)&.call(table)
        end

        # The tree filters apply the same condition to two different rows, so
        # they need to build it once per alias rather than rewrite a string.
        def pcf_paired_builder(tracker_field, values)
          return if pcf_id_list(values).nil?

          status_field = PAIRED_FILTERS.assoc(tracker_field)&.last
          merged = status_field && pcf_merge_pair?(tracker_field, status_field)

          lambda do |table|
            condition = pcf_tracker_condition(values, table)
            next condition unless merged

            status = pcf_status_condition(filters[status_field][:operator], filters[status_field][:values], table)
            status ? "#{condition} AND #{status}" : condition
          end
        end

        def pcf_status_builder(operator, values)
          return unless pcf_status_condition(operator, values, Issue.table_name)

          ->(table) { pcf_status_condition(operator, values, table) }
        end

        # True when this status filter is already folded into its tracker filter.
        def pcf_merged_away?(status_field)
          pair = PAIRED_FILTERS.rassoc(status_field)
          pair && pcf_merge_pair?(pair.first, status_field)
        end

        def pcf_root_condition(own_condition, root_condition, operator)
          condition =
            "((#{Issue.table_name}.id = #{Issue.table_name}.root_id AND #{own_condition})" \
            " OR (#{Issue.table_name}.root_id IN (SELECT root.id FROM #{Issue.table_name} root" \
            " #{pcf_visible_join('root')} WHERE #{pcf_visible_condition('root')}" \
            "#{pcf_and(root_condition)})))"

          pcf_negated?(operator) ? "NOT #{condition}" : condition
        end

        # EXISTS rather than parent_id IN (...): an issue without a parent then
        # satisfies "is not" without any explicit NULL handling.
        #
        # A nil condition means "any parent at all", which is what the "any" and
        # "none" operators ask. Every quantifier below accepts nil for the same
        # reason.
        def pcf_parent_condition(parent_condition, operator)
          subquery =
            "SELECT 1 FROM #{Issue.table_name} parent #{pcf_visible_join('parent')}" \
            " WHERE parent.id = #{Issue.table_name}.parent_id" \
            " AND #{pcf_visible_condition('parent')}#{pcf_and(parent_condition)}"

          "(#{pcf_negated?(operator) ? 'NOT EXISTS' : 'EXISTS'} (#{subquery}))"
        end

        # " AND <condition>", or nothing at all when there is no condition.
        def pcf_and(condition)
          condition.nil? ? '' : " AND #{condition}"
        end

        # "has a parent" and "has a child", meaning one this user is allowed to see.
        #
        # The structural filters used to ask the database instead of asking the
        # user's view of it: parent_id IS NOT NULL is true of an issue whose parent
        # sits in a project the user cannot open, and a NOT EXISTS over every child
        # counts children that are invisible. Both let an invisible relative change
        # the answer for a visible issue, which is the one thing the visibility
        # scoping exists to prevent. Testing for a *visible* relative keeps the two
        # readings from diverging.
        def pcf_visible_parent_exists(subject)
          "EXISTS (SELECT 1 FROM #{Issue.table_name} tparent #{pcf_visible_join('tparent')}" \
            " WHERE tparent.id = #{subject}.parent_id AND #{pcf_visible_condition('tparent')})"
        end

        def pcf_visible_child_exists(subject)
          "EXISTS (SELECT 1 FROM #{Issue.table_name} tchild #{pcf_visible_join('tchild')}" \
            " WHERE tchild.parent_id = #{subject}.id AND #{pcf_visible_condition('tchild')})"
        end

        def pcf_ancestor_condition(ancestor_condition, operator)
          subquery =
            "SELECT 1 FROM #{Issue.table_name} AS ancestor #{pcf_visible_join('ancestor')}" \
            " WHERE #{Issue.table_name}.lft > ancestor.lft AND #{Issue.table_name}.rgt < ancestor.rgt" \
            " AND #{Issue.table_name}.root_id = ancestor.root_id" \
            " AND #{pcf_visible_condition('ancestor')}#{pcf_and(ancestor_condition)}"

          "(#{pcf_negated?(operator) ? 'NOT EXISTS' : 'EXISTS'} (#{subquery}))"
        end

        # Mirror of pcf_ancestor_condition, looking down the subtree.
        def pcf_descendant_condition(descendant_condition, operator)
          subquery =
            "SELECT 1 FROM #{Issue.table_name} AS descendant #{pcf_visible_join('descendant')}" \
            " WHERE descendant.lft > #{Issue.table_name}.lft AND descendant.rgt < #{Issue.table_name}.rgt" \
            " AND descendant.root_id = #{Issue.table_name}.root_id" \
            " AND #{pcf_visible_condition('descendant')}#{pcf_and(descendant_condition)}"

          "(#{pcf_negated?(operator) ? 'NOT EXISTS' : 'EXISTS'} (#{subquery}))"
        end

        def pcf_child_condition(child_condition, operator)
          subquery =
            "SELECT 1 FROM #{Issue.table_name} child #{pcf_visible_join('child')}" \
            " WHERE child.parent_id = #{Issue.table_name}.id" \
            " AND #{pcf_visible_condition('child')}#{pcf_and(child_condition)}"

          "(#{pcf_negated?(operator) ? 'NOT EXISTS' : 'EXISTS'} (#{subquery}))"
        end

        # Values selected at different depths describe different ancestors, so
        # each depth gets its own condition and they are OR-ed. Picking
        # "(2) Bug" and "(3) Feature" therefore means what it says: the ancestor
        # two levels up is a Bug, or the one three levels up is a Feature. The
        # earlier implementation collapsed the selection onto the smallest depth
        # and silently answered a different question.
        def pcf_specific_parent_sql(values, operator, column)
          by_depth = pcf_parse_depth_values(values)
          return pcf_no_value_condition(operator) if by_depth.empty?

          conditions = by_depth.map do |depth, ids|
            pcf_specific_parent_condition("parent#{depth}.#{column} IN (#{ids.join(',')})", depth)
          end
          combined = conditions.size == 1 ? conditions.first : "(#{conditions.join(' OR ')})"

          pcf_negated?(operator) ? "NOT #{combined}" : combined
        end

        def pcf_specific_parent_condition(where_clause, depth)
          joins = (1..depth).map do |i|
            "INNER JOIN #{Issue.table_name} parent#{i} ON " +
              (i == 1 ? "#{Issue.table_name}.parent_id" : "parent#{i - 1}.parent_id") + " = parent#{i}.id" \
                                                                                        " #{pcf_visible_join("parent#{i}")}"
          end.join(' ')
          # Every level on the way up has to be visible, not just the one being
          # asked about: an invisible issue in the middle of the chain would
          # otherwise still connect the two ends.
          visible = (1..depth).map { |i| pcf_visible_condition("parent#{i}") }.join(' AND ')

          "#{Issue.table_name}.id IN " \
            "(SELECT #{pcf_join_order_hint}#{Issue.table_name}.id FROM #{Issue.table_name} #{joins}" \
            " WHERE #{visible} AND #{where_clause})"
        end

        # Trees holding a matching issue.
        def pcf_tree_subquery(condition)
          "SELECT DISTINCT tree.root_id FROM #{Issue.table_name} tree #{pcf_visible_join('tree')}" \
            " WHERE tree.root_id IS NOT NULL AND #{pcf_visible_condition('tree')} AND #{condition}"
        end

        # Trees holding a matching issue that has children, plus standalone
        # issues (no parent, no children) matching the same condition.
        # The child proves the parent is a parent, so it has to be visible too:
        # otherwise a hidden child is enough to put a visible parent in the answer.
        def pcf_tree_parent_subquery(builder)
          parent_match =
            "SELECT DISTINCT child.root_id FROM #{Issue.table_name} child" \
            " #{pcf_visible_join('child')}" \
            " INNER JOIN #{Issue.table_name} parent ON child.parent_id = parent.id" \
            " #{pcf_visible_join('parent')}" \
            " WHERE child.root_id IS NOT NULL AND #{pcf_visible_condition('child')}" \
            " AND #{pcf_visible_condition('parent')}" \
            " AND #{builder.call('parent')}"
          "#{parent_match} UNION #{pcf_standalone_subquery(builder)}"
        end

        # Trees holding an issue with a matching child, plus standalone issues.
        #
        # The parent is scoped as well as the child. It contributes its root_id to
        # the answer, so an invisible one would let a tree match on a relationship
        # the user cannot see either end of.
        def pcf_tree_child_subquery(builder)
          child_match =
            "SELECT DISTINCT parent.root_id FROM #{Issue.table_name} parent" \
            " #{pcf_visible_join('parent')}" \
            " WHERE parent.root_id IS NOT NULL AND #{pcf_visible_condition('parent')}" \
            " AND EXISTS (SELECT 1 FROM #{Issue.table_name} child" \
            " #{pcf_visible_join('child')} WHERE child.parent_id = parent.id" \
            " AND #{pcf_visible_condition('child')} AND #{builder.call('child')})"
          "#{child_match} UNION #{pcf_standalone_subquery(builder)}"
        end

        # An issue with no relatives, as this user sees it: no visible parent and no
        # visible child. An alias of its own rather than reusing the issues table
        # name, which shadowed the outer query and made the missing visibility
        # scoping here easy to read straight past.
        def pcf_standalone_subquery(builder)
          "SELECT DISTINCT solo.root_id FROM #{Issue.table_name} solo #{pcf_visible_join('solo')}" \
            " WHERE solo.root_id IS NOT NULL AND #{pcf_visible_condition('solo')}" \
            " AND #{builder.call('solo')}" \
            " AND NOT #{pcf_visible_parent_exists('solo')}" \
            " AND NOT #{pcf_visible_child_exists('solo')}"
        end
      end
    end
  end
end

IssueQuery.prepend(RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods)
