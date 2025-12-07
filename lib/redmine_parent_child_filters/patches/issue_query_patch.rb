require_dependency 'issue_query'
module RedmineParentChildFilters
  module Patches
    module IssueQueryPatch
      module InstanceMethods
        def initialize_available_filters_with_pcf
          initialize_available_filters_without_pcf
          min_depth = Setting.plugin_redmine_parent_child_filters['min_depth'].to_i
          max_depth = Setting.plugin_redmine_parent_child_filters['max_depth'].to_i

          add_available_filter(
            "root_id",
            :type => :tree, :label => :label_filter_root
          ) if Setting.plugin_redmine_parent_child_filters['enable_root_id_filter']

          add_available_filter(
            "root_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_root_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_root_tracker_id_filter']

          add_available_filter(
            "root_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_root_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_root_status_id_filter']

          add_available_filter(
            "parent_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_parent_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_parent_tracker_id_filter']

          add_available_filter(
            "parent_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_parent_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_parent_status_id_filter']

          add_available_filter(
            "a_parent_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_a_parent_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_a_parent_tracker_id_filter']

          add_available_filter(
            "a_parent_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_a_parent_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_a_parent_status_id_filter']

          add_available_filter(
            "a_specific_parent_tracker_id",
            type: :list,
            values: lambda {
              trackers.flat_map do |tracker|
                (min_depth..max_depth).map do |depth|
                  ["(#{depth}) #{tracker.name}", "#{tracker.id}:#{depth}"]
                end
              end
            },
            label: :label_filter_a_specific_parent_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_a_specific_parent_tracker_id_filter']

          add_available_filter(
            "a_specific_parent_status_id",
            type: :list,
            values: lambda {
              issue_statuses_values.flat_map do |status|
                (min_depth..max_depth).map do |depth|
                  ["(#{depth}) #{status.first}", "#{status.last}:#{depth}"]
                end
              end
            },
            label: :label_filter_a_specific_parent_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_a_specific_parent_status_id_filter']

          add_available_filter(
            "child_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_child_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_child_tracker_id_filter']

          add_available_filter(
            "child_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_child_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_child_status_id_filter']

          add_available_filter(
            "tree_has_parent_or_child",
            type: :list,
            values: [[l(:general_text_yes), '1'], [l(:general_text_no), '0']],
            label: :label_filter_tree_has_parent_or_child
          ) if Setting.plugin_redmine_parent_child_filters['enable_tree_has_parent_or_child_filter']

          add_available_filter(
            "tree_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_tree_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_tree_tracker_id_filter']

          add_available_filter(
            "tree_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_tree_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_tree_status_id_filter']

          add_available_filter(
            "tree_parent_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_tree_parent_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_tree_parent_tracker_id_filter']

          add_available_filter(
            "tree_parent_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_tree_parent_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_tree_parent_status_id_filter']

          add_available_filter(
            "tree_child_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_tree_child_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_tree_child_tracker_id_filter']

          add_available_filter(
            "tree_child_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_tree_child_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_tree_child_status_id_filter']
        end

        def sql_for_root_id_field(field, operator, value)
          case operator
          when "="
            # accepts a comma separated list of ids
            ids = value.first.to_s.scan(/\d+/)
            condition = ids.empty? ? "1=0" : "#{Issue.table_name}.root_id IN (#{ids.join(",")})"
          when "~"
            # accepts a comma separated list of ids
            ids = value.first.to_s.scan(/\d+/)
            condition = ids.empty? ? "1=0" : "#{Issue.table_name}.root_id IN (#{ids.join(",")})"
          when "!*"
            "#{Issue.table_name}.root_id IS NULL"
          when "*"
            "#{Issue.table_name}.root_id IS NOT NULL"
          else
            # type code here
          end
        end

        def sql_for_root_tracker_id_field(field, operator, value)
          if operator == '='
            # Include issues which are their own root and match the tracker condition
            # OR include issues where their root matches the tracker condition
            "((#{Issue.table_name}.id = #{Issue.table_name}.root_id AND #{Issue.table_name}.tracker_id IN (#{value.join(',')})) OR (#{Issue.table_name}.root_id IN (SELECT id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')}))))"
          elsif operator == '!'
            # Exclude issues which are their own root and match the tracker condition
            # OR exclude issues where their root matches the tracker condition
            "NOT ((#{Issue.table_name}.id = #{Issue.table_name}.root_id AND #{Issue.table_name}.tracker_id IN (#{value.join(',')})) OR (#{Issue.table_name}.root_id IN (SELECT id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')}))))"
          end
        end

        def sql_for_root_status_id_field(field, operator, value)
          case operator
          when '='
            "((#{Issue.table_name}.id = #{Issue.table_name}.root_id AND #{Issue.table_name}.status_id IN (#{value.join(',')})) OR (#{Issue.table_name}.root_id IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')}))))"
          when '!'
            "NOT ((#{Issue.table_name}.id = #{Issue.table_name}.root_id AND #{Issue.table_name}.status_id IN (#{value.join(',')})) OR (#{Issue.table_name}.root_id IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')}))))"
          when 'o'
            "((#{Issue.table_name}.id = #{Issue.table_name}.root_id AND #{Issue.table_name}.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_false})) OR (#{Issue.table_name}.root_id IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_false}))))"
          when 'c'
            "((#{Issue.table_name}.id = #{Issue.table_name}.root_id AND #{Issue.table_name}.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_true})) OR  (#{Issue.table_name}.root_id IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_true}))))"
          when '*'
            "(#{Issue.table_name}.id != #{Issue.table_name}.root_id)"
          end
        end

        def sql_for_parent_tracker_id_field(field, operator, value)
          if operator == '='
            "(#{Issue.table_name}.parent_id IN (SELECT id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')})))"
          elsif operator == '!'
            "(#{Issue.table_name}.parent_id NOT IN (SELECT id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')})) OR #{Issue.table_name}.parent_id IS NULL)"
          end
        end

        def sql_for_parent_status_id_field(field, operator, value)
          case operator
          when '='
            "(#{Issue.table_name}.parent_id IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')})))"
          when '!'
            "(#{Issue.table_name}.parent_id NOT IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')})) OR #{Issue.table_name}.parent_id IS NULL)"
          when 'o'  # open issues
            "(#{Issue.table_name}.parent_id IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_false})))"
          when 'c'  # closed issues
            "(#{Issue.table_name}.parent_id IN (SELECT id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_true})))"
          when '*'  # all issues
            nil  # return nil to include all issues regardless of status
          end
        end

        def sql_for_a_parent_tracker_id_field(field, operator, value)
          subquery = "EXISTS (SELECT 1  FROM #{Issue.table_name} AS ancestor  WHERE child.lft > ancestor.lft  AND child.rgt < ancestor.rgt  AND child.root_id = ancestor.root_id  AND ancestor.tracker_id IN (#{value.join(',')}))"

          case operator
          when '='
            "(#{Issue.table_name}.id IN (SELECT child.id FROM #{Issue.table_name} AS child WHERE #{subquery}))"
          when '!'
            "(#{Issue.table_name}.id NOT IN (SELECT child.id FROM #{Issue.table_name} AS child WHERE #{subquery}))"
          end
        end

        def sql_for_a_parent_status_id_field(field, operator, value)
          subquery = "EXISTS (SELECT 1  FROM #{Issue.table_name} AS ancestor  WHERE child.lft > ancestor.lft  AND child.rgt < ancestor.rgt  AND child.root_id = ancestor.root_id  AND ancestor.status_id IN (#{value.join(',')}))"

          case operator
          when '='
            "(#{Issue.table_name}.id IN (SELECT child.id FROM #{Issue.table_name} AS child WHERE #{subquery}))"
          when '!'
            "(#{Issue.table_name}.id NOT IN (SELECT child.id FROM #{Issue.table_name} AS child WHERE #{subquery}))"
          when 'o'  # open issues
            open_subquery = "EXISTS (SELECT 1  FROM #{Issue.table_name} AS ancestor  WHERE child.lft > ancestor.lft  AND child.rgt < ancestor.rgt  AND child.root_id = ancestor.root_id  AND ancestor.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_false}))"
            "(#{Issue.table_name}.id IN (SELECT child.id FROM #{Issue.table_name} AS child WHERE #{open_subquery}))"
          when 'c'  # closed issues
            closed_subquery = "EXISTS (SELECT 1  FROM #{Issue.table_name} AS ancestor  WHERE child.lft > ancestor.lft  AND child.rgt < ancestor.rgt  AND child.root_id = ancestor.root_id  AND ancestor.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_true}))"
            "(#{Issue.table_name}.id IN (SELECT child.id FROM #{Issue.table_name} AS child WHERE #{closed_subquery}))"
          when '*'  # all issues
            nil  # return nil to include all issues regardless of status
          end
        end

        def sql_for_a_specific_parent_tracker_id_field(field, operator, value)
          tracker_ids, depths = value.map { |v| v.split(':') }.transpose
          depth = depths.min.to_i
          joins = (1..depth).map { |i| "INNER JOIN #{Issue.table_name} parent#{i} ON " + (i == 1 ? "#{Issue.table_name}.parent_id" : "parent#{i-1}.parent_id") + " = parent#{i}.id" }.join(' ')

          where_clause = "parent#{depth}.tracker_id IN (#{tracker_ids.join(',')})"

          case operator
          when '='
            "#{Issue.table_name}.id IN (SELECT #{Issue.table_name}.id FROM #{Issue.table_name} #{joins} WHERE #{where_clause})"
          when '!'
            "#{Issue.table_name}.id NOT IN (SELECT #{Issue.table_name}.id FROM #{Issue.table_name} #{joins} WHERE #{where_clause})"
          end
        end

        def sql_for_a_specific_parent_status_id_field(field, operator, value)
          status_ids, depths = value.map { |v| v.split(':') }.transpose
          depth = depths.min.to_i

          joins = (1..depth).map { |i| "INNER JOIN #{Issue.table_name} parent#{i} ON " + (i == 1 ? "#{Issue.table_name}.parent_id" : "parent#{i-1}.parent_id") + " = parent#{i}.id" }.join(' ')

          where_clause = "parent#{depth}.status_id IN (#{status_ids.join(',')})"

          case operator
          when '='
            "#{Issue.table_name}.id IN (SELECT #{Issue.table_name}.id FROM #{Issue.table_name} #{joins} WHERE #{where_clause})"
          when '!'
            "#{Issue.table_name}.id NOT IN (SELECT #{Issue.table_name}.id FROM #{Issue.table_name} #{joins} WHERE #{where_clause})"
          end
        end

        def sql_for_child_tracker_id_field(field, operator, value)
          tracker_filter = ''
          case operator
          when '=', '!'
            status_condition = ''

            if filters && filters.key?('child_status_id')
              status_filter = filters['child_status_id']
              status_operator = status_filter[:operator]
              status_values = status_filter[:values]

              case status_operator
              when '=', '!'
                status_condition = "AND status_id #{status_operator == '=' ? 'IN' : 'NOT IN'} (#{status_values.join(',')})"
              when 'o'
                status_condition = "AND status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_false})"
              when 'c'
                status_condition = "AND status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_true})"
              when '*'
                status_condition = ''
              end
            end

            tracker_filter = "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE tracker_id #{operator == '=' ? 'IN' : 'NOT IN'} (#{value.join(',')}) #{status_condition}))"
          end
          tracker_filter
        end

        def sql_for_child_status_id_field(field, operator, value)
          status_filter = ''
          case operator
          when '='
            status_filter = "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')})))"
          when '!'
            status_filter = "(#{Issue.table_name}.id NOT IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')})) OR #{Issue.table_name}.parent_id IS NULL)"
          when 'o'
            status_filter = "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_false})))"
          when 'c'
            status_filter = "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_true})))"
          when '*'
            status_filter = "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name}))"
          end unless filters && filters.key?('child_tracker_id')
          status_filter
        end

        def sql_for_tree_has_parent_or_child_field(field, operator, value)
          tree_scope = "SELECT DISTINCT scope.root_id FROM #{Issue.table_name} scope WHERE scope.parent_id IS NOT NULL OR EXISTS (SELECT 1 FROM #{Issue.table_name} child WHERE child.parent_id = scope.id)"
          tree_condition(tree_scope, operator, value.include?('yes') || value.include?('1'))
        end

        def sql_for_tree_tracker_id_field(field, operator, value)
          subquery = "SELECT DISTINCT tree.root_id FROM #{Issue.table_name} tree WHERE tree.tracker_id IN (#{value.join(',')})"
          tree_condition(subquery, operator)
        end

        def sql_for_tree_status_id_field(field, operator, value)
          status_condition = case operator
                             when '=', '!'
                               "tree.status_id IN (#{value.join(',')})"
                             when 'o'
                               "tree.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_false})"
                             when 'c'
                               "tree.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_true})"
                             when '*'
                               nil
                             end

          return if status_condition.nil?

          subquery = "SELECT DISTINCT tree.root_id FROM #{Issue.table_name} tree WHERE #{status_condition}"
          tree_condition(subquery, operator)
        end

        def sql_for_tree_parent_tracker_id_field(field, operator, value)
          parent_match = "SELECT DISTINCT child.root_id FROM #{Issue.table_name} child INNER JOIN #{Issue.table_name} parent ON child.parent_id = parent.id WHERE parent.tracker_id IN (#{value.join(',')})"
          single_match = "SELECT DISTINCT #{Issue.table_name}.root_id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')}) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM #{Issue.table_name} child WHERE child.parent_id = #{Issue.table_name}.id)"
          subquery = "#{parent_match} UNION #{single_match}"
          tree_condition(subquery, operator)
        end

        def sql_for_tree_parent_status_id_field(field, operator, value)
          status_condition = case operator
                             when '='
                               "parent.status_id IN (#{value.join(',')})"
                             when '!'
                               "parent.status_id IN (#{value.join(',')})"
                             when 'o'
                               "parent.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_false})"
                             when 'c'
                               "parent.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_true})"
                             when '*'
                               nil
                             end

          return if status_condition.nil?

          parent_match = "SELECT DISTINCT child.root_id FROM #{Issue.table_name} child INNER JOIN #{Issue.table_name} parent ON child.parent_id = parent.id WHERE #{status_condition}"
          single_match = "SELECT DISTINCT #{Issue.table_name}.root_id FROM #{Issue.table_name} WHERE #{status_condition.gsub('parent.', '')} AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM #{Issue.table_name} child WHERE child.parent_id = #{Issue.table_name}.id)"
          subquery = "#{parent_match} UNION #{single_match}"

          tree_condition(subquery, operator)
        end

        def sql_for_tree_child_tracker_id_field(field, operator, value)
          child_match = "SELECT DISTINCT parent.root_id FROM #{Issue.table_name} parent WHERE EXISTS (SELECT 1 FROM #{Issue.table_name} child WHERE child.parent_id = parent.id AND child.tracker_id IN (#{value.join(',')}))"
          single_match = "SELECT DISTINCT #{Issue.table_name}.root_id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')}) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM #{Issue.table_name} child WHERE child.parent_id = #{Issue.table_name}.id)"
          subquery = "#{child_match} UNION #{single_match}"
          tree_condition(subquery, operator)
        end

        def sql_for_tree_child_status_id_field(field, operator, value)
          status_condition = case operator
                             when '=', '!'
                               "child.status_id IN (#{value.join(',')})"
                             when 'o'
                               "child.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_false})"
                             when 'c'
                               "child.status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed=#{self.class.connection.quoted_true})"
                             when '*'
                               nil
                             end

          return if status_condition.nil?

          child_match = "SELECT DISTINCT parent.root_id FROM #{Issue.table_name} parent WHERE EXISTS (SELECT 1 FROM #{Issue.table_name} child WHERE child.parent_id = parent.id AND #{status_condition})"
          single_match = "SELECT DISTINCT #{Issue.table_name}.root_id FROM #{Issue.table_name} WHERE #{status_condition.gsub('child.', '')} AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM #{Issue.table_name} child WHERE child.parent_id = #{Issue.table_name}.id)"
          subquery = "#{child_match} UNION #{single_match}"
          tree_condition(subquery, operator)
        end

        def tree_condition(subquery, operator, positive = true)
          case operator
          when '='
            positive ? "#{Issue.table_name}.root_id IN (#{subquery})" : "#{Issue.table_name}.root_id NOT IN (#{subquery})"
          when '!'
            positive ? "#{Issue.table_name}.root_id NOT IN (#{subquery})" : "#{Issue.table_name}.root_id IN (#{subquery})"
          when 'o', 'c'
            "#{Issue.table_name}.root_id IN (#{subquery})"
          else
            positive ? "#{Issue.table_name}.root_id IN (#{subquery})" : "#{Issue.table_name}.root_id NOT IN (#{subquery})"
          end
        end

      end
    end
  end
end

IssueQuery.include(RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods)
IssueQuery.class_eval do
  alias_method :initialize_available_filters_without_pcf, :initialize_available_filters
  alias_method :initialize_available_filters, :initialize_available_filters_with_pcf
end
