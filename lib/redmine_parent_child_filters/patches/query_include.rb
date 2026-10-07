# frozen_string_literal: true

# Adds the "is not" operator to date filters (start date, due date, ...), and
# validates its values; and adds the filter type of the status filters that
# offer "none".
#
# The operator hash is replaced rather than mutated in place: operators_by_filter_type
# is a class_attribute whose default hash is shared with every Query subclass, and
# mutating it makes the change impossible to reason about (and to undo) once other
# plugins hold a reference to the same array.

require_dependency 'query'

module RedmineParentChildFilters
  module Patches
    module QueryInclude
      # Redmine's :list_status offers "any" but not "none". The status filters of
      # this plugin whose relative may be missing (a parent, a subtask, a link in
      # the tree) offer "none" as well (Jan, 2026-10-07), so they get a type of
      # their own: :list_status plus "none", just before "any" as on Redmine's
      # optional lists. Redmine's own status filter keeps :list_status.
      # assets/javascripts/pcf_filters.js renders the type in the filter form.
      STATUS_WITH_NONE = :pcf_list_status

      def self.apply!
        add_date_not_operator
        add_status_with_none_type
      end

      def self.add_date_not_operator
        operators = Query.operators_by_filter_type
        date_operators = operators[:date]
        return if date_operators.nil? || date_operators.include?('!')

        # Deliberately not frozen: another plugin may legitimately append its own
        # operator to the same array.
        Query.operators_by_filter_type = operators.merge(
          :date => date_operators.dup.insert(3, '!')
        )
      end

      def self.add_status_with_none_type
        operators = Query.operators_by_filter_type
        status_operators = operators[:list_status]
        return if status_operators.nil? || operators.key?(STATUS_WITH_NONE)

        with_none = status_operators.dup
        with_none.insert(with_none.index('*') || with_none.size, '!*') unless with_none.include?('!*')
        Query.operators_by_filter_type = operators.merge(STATUS_WITH_NONE => with_none)
      end

      # Redmine checks the values of "=", ">=", "<=" and "><" on a date filter,
      # but has no case for "is not", and its sql_for_field puts those values
      # into a NOT IN unchecked: a value that is no date answered 500 on
      # PostgreSQL and matched every issue on MariaDB. A plain date is what the
      # date picker sends and what a date column or a date custom field holds.
      module DateValidation
        DATE = /\A\d{4}-\d{2}-\d{2}\z/.freeze

        def validate_query_filters
          super

          filters&.each_key do |field|
            next unless type_for(field) == :date && operator_for(field) == '!'
            next unless (values_for(field) || []).any? { |v| v.present? && !pcf_date?(v) }

            add_filter_error(field, :invalid)
          end
        end

        private

        def pcf_date?(value)
          DATE.match?(value.to_s) && Date.valid_date?(*value.to_s.split('-').map(&:to_i))
        end
      end
    end
  end
end

RedmineParentChildFilters::Patches::QueryInclude.apply!
Query.prepend(RedmineParentChildFilters::Patches::QueryInclude::DateValidation)
