require_dependency 'query'
module RedmineParentChildFilters
  module Patches
    module QueryInclude
      def self.included(base)
        if base.operators_by_filter_type.key?(:date)
          base.operators_by_filter_type[:date].insert(3, "!") unless base.operators_by_filter_type[:date].include?('!')
        end
      end
    end
  end
end

Query.include(RedmineParentChildFilters::Patches::QueryInclude)
