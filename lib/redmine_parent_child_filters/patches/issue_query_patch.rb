require_dependency 'issue_query'
module RedmineParentChildFilters
  module Patches
    module IssueQueryPatch
      module InstanceMethods
        def initialize_available_filters
          super
          add_available_filter(
            "parent_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :parent_tracker_id
          )
          add_available_filter(
            "parent_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :parent_status_id
          )
          add_available_filter(
            "child_tracker_id",
            type: :list, values: trackers.collect { |s| [s.name, s.id.to_s] }, label: :child_tracker_id
          )
          add_available_filter(
            "child_status_id",
            type: :list_status, values: lambda { issue_statuses_values }, label: :child_status_id
          )
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

        def sql_for_child_tracker_id_field(field, operator, value)
          if operator == '='
            "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')})))"
          elsif operator == '!'
            "(#{Issue.table_name}.id NOT IN (SELECT parent_id FROM #{Issue.table_name} WHERE tracker_id IN (#{value.join(',')})) OR #{Issue.table_name}.id NOT IN (SELECT parent_id FROM #{Issue.table_name}))"
          end
        end

        def sql_for_child_status_id_field(field, operator, value)
          case operator
          when '='
            "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')})))"
          when '!'
            "(#{Issue.table_name}.id NOT IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (#{value.join(',')})) OR #{Issue.table_name}.id NOT IN (SELECT parent_id FROM #{Issue.table_name}))"
          when 'o'  # open issues
            "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_false})))"
          when 'c'  # closed issues
            "(#{Issue.table_name}.id IN (SELECT parent_id FROM #{Issue.table_name} WHERE status_id IN (SELECT id FROM #{IssueStatus.table_name} WHERE is_closed = #{ActiveRecord::Base.connection.quoted_true})))"
          when '*'  # all issues
            nil  # return nil to include all issues regardless of status
          end
        end

      end
    end
  end
end

IssueQuery.prepend(RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods)