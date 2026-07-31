# frozen_string_literal: true

# Groups the filters added by this plugin under a dedicated optgroup in the
# "Add filter" dropdown.
#
# Redmine's own filters_options_for_select is reused as-is: the plugin's filters
# are hidden from it and the resulting optgroup is appended afterwards. That way
# upstream changes to the grouping of core filters keep working, and disabling
# this patch only costs the grouping, never the filters themselves.

require_dependency 'queries_helper'

module RedmineParentChildFilters
  module Patches
    module QueriesHelperPatch
      module InstanceMethods
        # The hierarchy filters, taken from the query patch so that the list
        # cannot drift: a filter added there is grouped here automatically. Read
        # lazily rather than at load time so this file does not care which patch
        # init.rb requires first.
        #
        # The people filters (involved / mentioned) are deliberately absent: they
        # are not about the issue hierarchy, so Redmine groups them with the
        # other person filters where users already look for them.
        def pcf_grouped_filters
          RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods::FILTER_ORDER
        end

        def filters_options_for_select(query)
          available_filters = query.available_filters
          plugin_filters = pcf_grouped_filters & available_filters.keys
          return super if plugin_filters.empty?

          begin
            query.instance_variable_set(:@available_filters, available_filters.except(*plugin_filters))
            options = super
          ensure
            query.instance_variable_set(:@available_filters, available_filters)
          end

          options + grouped_options_for_select(
            [[l(:label_filter_group_parent_child),
              plugin_filters.map { |field| [available_filters[field][:name], field] }]]
          )
        end
      end
    end
  end
end

QueriesHelper.prepend(RedmineParentChildFilters::Patches::QueriesHelperPatch::InstanceMethods)
