require_dependency 'issue_query'
module RedmineParentChildFilters
  module Patches
    module IssueQueryPatch
      module InstanceMethods
        def initialize_available_filters_with_pcf
          initialize_available_filters_without_pcf

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
            "child_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :label_filter_child_tracker_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_child_tracker_id_filter']

          add_available_filter(
            "child_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :label_filter_child_status_id
          ) if Setting.plugin_redmine_parent_child_filters['enable_child_status_id_filter']
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

      end
    end
  end
end

IssueQuery.include(RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods)
IssueQuery.class_eval do
  alias_method :initialize_available_filters_without_pcf, :initialize_available_filters
  alias_method :initialize_available_filters, :initialize_available_filters_with_pcf
end
