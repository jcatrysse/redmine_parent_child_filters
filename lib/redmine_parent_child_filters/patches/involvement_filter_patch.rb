# frozen_string_literal: true

require_dependency 'issue_query'
require File.expand_path('filter_registration', __dir__)
require File.expand_path('principal_filter_support', __dir__)

# Redmine joins its filters with AND and offers no OR between them, so a
# question like "issues where I am the assignee, the author or a watcher"
# cannot be asked with the stock filters.
#
# Rather than teaching Query to OR arbitrary filters, which would change the
# meaning of every saved query and every other query class, this registers one
# filter whose SQL is a parenthesised OR. That is the same shape Redmine itself
# uses in sql_for_watcher_id_field, and it needs no core change: a filter may
# return any condition, and Redmine ANDs it with the rest.
module RedmineParentChildFilters
  module Patches
    module InvolvementFilterPatch
      module InstanceMethods
        include FilterRegistration
        include PrincipalFilterSupport

        def initialize_available_filters
          super

          pcf_register_filter('involved_id', :type => :list, :values => lambda { pcf_principal_values })
        end

        def sql_for_involved_id_field(field, operator, value)
          ids = pcf_principal_ids(value)
          return pcf_no_principal_condition(operator) if ids.empty?

          condition = "(#{pcf_involvement_legs(ids).join(' OR ')})"
          operator == '!' ? "NOT #{condition}" : condition
        end
      end
    end
  end
end

IssueQuery.prepend(RedmineParentChildFilters::Patches::InvolvementFilterPatch::InstanceMethods)
