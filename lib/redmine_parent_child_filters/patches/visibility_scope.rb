# frozen_string_literal: true

module RedmineParentChildFilters
  module Patches
    # Keeping a filter from answering about an issue the user may not see.
    #
    # Its own file because it is the security critical part: a reader looking for
    # "where does this apply permissions" should find it without reading six
    # hundred lines of SQL builders. COMPATIBILITY.md explains the one assumption
    # it makes about Redmine.
    module VisibilityScope
      # Restricts a relative to the issues the current user is allowed to see.
      #
      # The outer query is scoped by Redmine, but these subqueries read the
      # issues table themselves, so without this a visible issue could be made
      # to match on the tracker, status or history of a relative the user may
      # not see. No id or subject ever leaked, but the answer did: "this issue
      # has a closed Bug below it" is itself information.
      #
      # Issue.visible_condition is core's reusable form of the Issue.visible
      # scope, written against the issues and projects tables. Rewriting those
      # two table names to reach an alias is the idiom core uses itself, in the
      # total_estimated_hours column of IssueQuery. It is safe here because the
      # condition carries no user supplied strings: only numeric ids and the
      # module name issue_tracking, which neither pattern can match.
      def pcf_visible_join(table)
        "INNER JOIN #{Project.table_name} #{table}_projects" \
          " ON #{table}_projects.id = #{table}.project_id"
      end

      def pcf_visible_condition(table)
        "(#{pcf_own_visible_condition
                .gsub(/\b#{Issue.table_name}\b/, table)
                .gsub(/\b#{Project.table_name}\b/, "#{table}_projects")})"
      end

      # Building the condition reads the user's roles and groups, and a tree
      # filter needs it for several aliases in one statement. Keyed on the user
      # so a changed User.current is never answered from a stale memo.
      def pcf_own_visible_condition
        @pcf_visible_conditions ||= {}
        @pcf_visible_conditions[User.current.id] ||= Issue.visible_condition(User.current)
      end
    end
  end
end
