# frozen_string_literal: true

require_dependency 'issue_query'
require File.expand_path('value_parsing', __dir__)

# Shared by the filters that take a principal rather than a tracker or a status,
# so that the involvement filter and the mention filter cannot drift apart in how
# they read "me" or how they define being involved.
module RedmineParentChildFilters
  module Patches
    module PrincipalFilterSupport
      # pcf_parse_ids comes from here. It would resolve anyway, because everything is
      # mixed into the same IssueQuery and another module already includes it — but
      # depending on that is depending on load order, and this module would break on a
      # reordering it has no part in. Stated locally instead.
      include ValueParsing

      private

      # Same shape as Redmine's own principal value lists: "me" first, then the
      # principals of the project, carrying their status so the interface can
      # group them. Groups are dropped for the filters that need a login.
      def pcf_principal_values(users_only: false)
        values = []
        values << ["<< #{l(:label_me)} >>", 'me'] if User.current.logged?
        candidates = users_only ? users : principals
        values +
          candidates.sort_by { |p| [p.status, p] }
                    .collect { |p| [p.name, p.id.to_s, l("status_#{User::LABEL_BY_STATUS[p.status]}")] }
      end

      # Query#statement substitutes "me" only for a hard coded list of field
      # names, so a filter added by a plugin has to do it itself. Groups are
      # included because an issue can be assigned to, or watched by, a group;
      # they simply never match an author or a mention.
      # The ids read strictly, the same way the hierarchy filters read theirs.
      #
      # This used to use core's scan(/\d+/), which turns "1 OR 2" into principals 1
      # and 2 and "user-123" into principal 123. Neither can inject SQL, so it was
      # never a hole, but value_parsing.rb already spells out why that reading is
      # wrong: a corrupted saved query or a mistyped url then quietly answers about
      # real people. Two standards for the same kind of value in one plugin is not a
      # position worth defending, so there is now one.
      #
      # "me" stays special: Query#statement only substitutes it for a hard coded list
      # of core field names, so a plugin filter has to expand it itself.
      def pcf_principal_ids(values)
        Array(values).flat_map do |value|
          if value == 'me'
            User.current.logged? ? [User.current.id] + User.current.group_ids : [0]
          else
            pcf_parse_ids(value)
          end
        end.uniq.sort
      end

      # Being involved, as separate conditions so that a filter can extend the
      # list without repeating them.
      def pcf_involvement_legs(ids)
        list = ids.join(',')
        [
          "#{Issue.table_name}.author_id IN (#{list})",
          # assigned_to_id is nullable, and NULL IN (...) is UNKNOWN rather than
          # false, which would swallow unassigned issues under a NOT.
          "(#{Issue.table_name}.assigned_to_id IS NOT NULL AND #{Issue.table_name}.assigned_to_id IN (#{list}))",
          # Redmine's own watcher condition, so that watchers of other users stay
          # behind the view_issue_watchers permission.
          sql_for_watcher_id_field('watcher_id', '=', ids.map(&:to_s))
        ]
      end

      def pcf_no_principal_condition(operator)
        operator == '!' ? '1=1' : '1=0'
      end
    end
  end
end
