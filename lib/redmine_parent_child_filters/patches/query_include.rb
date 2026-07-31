# frozen_string_literal: true

# Adds the "is not" operator to date filters (start date, due date, ...).
#
# The operator hash is replaced rather than mutated in place: operators_by_filter_type
# is a class_attribute whose default hash is shared with every Query subclass, and
# mutating it makes the change impossible to reason about (and to undo) once other
# plugins hold a reference to the same array.

require_dependency 'query'

module RedmineParentChildFilters
  module Patches
    module QueryInclude
      def self.apply!
        operators = Query.operators_by_filter_type
        date_operators = operators[:date]
        return if date_operators.nil? || date_operators.include?('!')

        # Deliberately not frozen: another plugin may legitimately append its own
        # operator to the same array.
        Query.operators_by_filter_type = operators.merge(
          :date => date_operators.dup.insert(3, '!')
        )
      end
    end
  end
end

RedmineParentChildFilters::Patches::QueryInclude.apply!
