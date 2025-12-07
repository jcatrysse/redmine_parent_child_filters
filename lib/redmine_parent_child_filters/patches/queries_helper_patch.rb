# This patch can be ommited, it only makes the new filters available in a group, as opposed to ungrouped.

require_dependency 'queries_helper'
module RedmineParentChildFilters
  module Patches
    module QueriesHelperPatch
      module InstanceMethods
        def filters_options_for_select(query)
          new_filters = %w[root_id root_tracker_id root_status_id parent_id parent_tracker_id parent_status_id a_parent_tracker_id a_parent_status_id a_specific_parent_tracker_id a_specific_parent_status_id child_id child_tracker_id child_status_id tree_has_parent_or_child tree_tracker_id tree_parent_tracker_id tree_parent_status_id tree_child_tracker_id tree_child_status_id]
          new_group = :label_filter_group_parent_child
          ungrouped = []
          grouped = {}
          query.available_filters.map do |field, field_options|
            if new_filters.include?(field)
              group = new_group
            elsif field_options[:type] == :relation
              group = :label_relations
            elsif field_options[:type] == :tree
              group = query.is_a?(IssueQuery) ? :label_relations : nil
            elsif /^cf_\d+\./.match?(field)
              group = (field_options[:through] || field_options[:field]).try(:name)
            elsif field =~ /^(.+)\./
              # association filters
              group = "field_#{$1}".to_sym
            elsif %w(member_of_group assigned_to_role).include?(field)
              group = :field_assigned_to
            elsif field_options[:type] == :date_past || field_options[:type] == :date
              group = :label_date
            elsif %w(estimated_hours spent_time).include?(field)
              group = :label_time_tracking
            end
            if group
              (grouped[group] ||= []) << [field_options[:name], field]
            else
              ungrouped << [field_options[:name], field]
            end
          end
          # Don't group dates if there's only one (eg. time entries filters)
          if grouped[:label_date].try(:size) == 1
            ungrouped << grouped.delete(:label_date).first
          end
          s = options_for_select([[]] + ungrouped)
          if grouped.present?
            localized_grouped = grouped.map {|k, v| [k.is_a?(Symbol) ? l(k) : k.to_s, v]}
            s << grouped_options_for_select(localized_grouped)
          end
          s
        end
      end
    end
  end
end

QueriesHelper.include IssuesHelper
QueriesHelper.prepend(RedmineParentChildFilters::Patches::QueriesHelperPatch::InstanceMethods)
ActionView::Base.prepend QueriesHelper
IssuesController.prepend QueriesHelper
