# frozen_string_literal: true

require_dependency 'issue_query'
require File.expand_path('filter_registration', __dir__)
require File.expand_path('value_parsing', __dir__)

# Filters on where an issue has been, rather than where it is.
#
# Redmine journals every move: Issue#journalized_attribute_names includes
# project_id, so a move writes a journal detail with the old and the new project,
# for the issue and for every subtask that moves along with it. Core already has
# the operators to read that history ("has been", "has never been", "changed
# from") and builds them generically in Query#sql_for_field for any journalized
# column. It simply never gives them to the project filter, which is a :list.
#
# project_history_id is therefore core's own SQL, under a filter of its own:
# core's project_id filter is left exactly as it is, and the new one is also
# available inside a project, where core offers no project filter at all.
#
# first_project_id has no counterpart in core, because "has been" says whether a
# value ever occurred and not when. It is built from the same pieces: the oldest
# project change, in the order the issue history shows it, says where the issue
# came from; an issue that never moved is still where it was created.
module RedmineParentChildFilters
  module Patches
    module ProjectHistoryFilterPatch
      module InstanceMethods
        include FilterRegistration
        include ValueParsing

        def initialize_available_filters
          super

          # Core's own list, so "my projects" and "my bookmarks" are offered the
          # way they are on core's project filter.
          pcf_register_filter('project_history_id',
                              :type => pcf_project_history_type, :values => lambda { project_values })
          pcf_register_filter('first_project_id', :type => :list, :values => lambda { project_values })
        end

        def sql_for_project_history_id_field(field, operator, value)
          ids = pcf_project_ids(value)
          return pcf_no_value_condition(operator) if ids.empty?

          case operator
          when '='
            "#{Issue.table_name}.project_id IN (#{ids.join(',')})"
          when '!'
            # project_id is NOT NULL, so NOT IN loses no issue.
            "#{Issue.table_name}.project_id NOT IN (#{ids.join(',')})"
          when 'ev', '!ev', 'cf'
            # Redmine 5.0 has no history operators: sql_for_field raises
            # QueryError for them. A value can still arrive from a hand written
            # url, so the condition is dropped, as it is for the status filters.
            return unless pcf_project_history_supported?

            "(#{sql_for_field('project_id', operator, ids.map(&:to_s), Issue.table_name, 'project_id')})"
          end
        end

        def sql_for_first_project_id_field(field, operator, value)
          ids = pcf_project_ids(value)
          return pcf_no_value_condition(operator) if ids.empty?

          # Every issue has exactly one first project, so "is not" is simply the
          # negation and needs no quantifier of its own.
          condition = "(#{pcf_moved_from_condition(ids)} OR " \
                      "(#{Issue.table_name}.project_id IN (#{ids.join(',')}) AND NOT EXISTS (#{pcf_project_moves('pcf_moves')})))"
          operator == '!' ? "NOT #{condition}" : condition
        end

        private

        def pcf_project_history_supported?
          Query.operators_by_filter_type.key?(:list_with_history)
        end

        # :list_with_history exists from Redmine 5.1. On 5.0 the filter still
        # works, with "is" and "is not" only.
        def pcf_project_history_type
          pcf_project_history_supported? ? :list_with_history : :list
        end

        # Query#statement expands "mine" and "bookmarks" only for a field named
        # project_id, so a plugin filter offering core's project list has to
        # expand them itself, the same way. Everything else must be a whole id.
        def pcf_project_ids(values)
          Array(values).flat_map do |value|
            case value
            when 'mine' then User.current.memberships.pluck(:project_id)
            when 'bookmarks' then User.current.bookmarked_project_ids.map(&:to_i)
            else pcf_parse_ids(value)
            end
          end.uniq.sort
        end

        # The oldest project change of the issue moved it away from one of ids.
        #
        # "Oldest" is the order the issue history is shown in: created_on, then
        # the journal id. The detail id settles the one case left, two project
        # changes in one journal, which the issue form cannot produce but a script
        # saving the same issue object twice does.
        def pcf_moved_from_condition(ids)
          old_values = ids.map { |id| self.class.connection.quote(id.to_s) }.join(',')

          "EXISTS (#{pcf_project_moves('pcf_first')}" \
            " AND pcf_first_details.old_value IN (#{old_values})" \
            " AND NOT EXISTS (#{pcf_project_moves('pcf_earlier')}" \
            " AND (pcf_earlier.created_on < pcf_first.created_on" \
            " OR (pcf_earlier.created_on = pcf_first.created_on AND pcf_earlier.id < pcf_first.id)" \
            " OR (pcf_earlier.id = pcf_first.id AND pcf_earlier_details.id < pcf_first_details.id))))"
        end

        # The project changes of the outer issue, as journal <alias> joined to its
        # details <alias>_details.
        #
        # Core's history operators skip journals the user may not read, and so
        # does this: Journal#split_private_notes keeps changes out of private
        # journals, but a journal can be made private afterwards, and a filter
        # must not answer from a change the user cannot see in the history.
        # The condition names journals, which is rewritten to the alias, and
        # projects, which is the project of the outer issue, exactly as in core.
        def pcf_project_moves(alias_name)
          details = "#{alias_name}_details"
          notes = Journal.visible_notes_condition(User.current, :skip_pre_condition => true)
                         .gsub(/\b#{Journal.table_name}\b/, alias_name)

          "SELECT 1 FROM #{Journal.table_name} #{alias_name}" \
            " INNER JOIN #{JournalDetail.table_name} #{details} ON #{details}.journal_id = #{alias_name}.id" \
            " WHERE #{alias_name}.journalized_type = 'Issue'" \
            " AND #{alias_name}.journalized_id = #{Issue.table_name}.id" \
            " AND #{details}.property = 'attr' AND #{details}.prop_key = 'project_id'" \
            " AND #{notes}"
        end
      end
    end
  end
end

IssueQuery.prepend(RedmineParentChildFilters::Patches::ProjectHistoryFilterPatch::InstanceMethods)
