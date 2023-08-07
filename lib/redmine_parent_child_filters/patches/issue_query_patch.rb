require_dependency 'issue_query'
module RedmineParentChildFilters
  module Patches
    module IssueQueryPatch
      module InstanceMethods
        def initialize_available_filters_with_pcf
          initialize_available_filters_without_pcf
          add_available_filter(
            "rootissue_id",
            :type => :tree, :label => :label_rootissue)
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

        def sql_for_rootissue_id_field(field, operator, value)
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
