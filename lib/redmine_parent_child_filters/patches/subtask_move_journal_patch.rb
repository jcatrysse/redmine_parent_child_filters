# frozen_string_literal: true

require_dependency 'issue'

# Gives a subtask a journal when Redmine moves it along with its parent.
#
# When an issue moves to another project, Issue#after_project_change moves every
# subtask that was in the same project, with child.send(:project=, project, true)
# and child.save, but never calls init_journal on the child. The parent's history
# shows the move, the subtask's history does not, and nothing in the database
# says where the subtask came from. Redmine's own "has been" and this plugin's
# project filters can only answer from the history, so they read such a subtask
# as having always been where it is now.
#
# This journals that move the way a move from the issue form is journaled: by the
# user who moved the parent, with every attribute the move changed, such as the
# project and a version that is not shared with the new project. It does not
# repair the past: subtasks moved before this was installed stay untraceable.
#
# Only the move core itself makes is touched. The scope is the duration of the
# parent's after_project_change, and only when the parent's own move is
# journaled: a script that moves the parent silently moves its subtasks silently
# too, so the two histories never disagree. A subtask that already carries a
# journal is left alone, so nothing is journaled twice.
#
# The journal sends no notification. The move of the parent already did, and a
# mail per subtask for a change nobody made by hand would be noise. Everything
# else a journal does still happens, as it would for a move made by hand:
# Redmine may add the mover as a watcher, depending on their preferences.
module RedmineParentChildFilters
  module Patches
    module SubtaskMoveJournalPatch
      # Who moves subtasks right now, if anyone. Thread.current is fiber local,
      # which is what this needs: the scope is one call stack.
      MOVER = :redmine_parent_child_filters_subtask_mover

      def project=(project, keep_tracker = false)
        mover = Thread.current[MOVER]
        init_journal(mover).notify = false if mover && persisted? && current_journal.nil? && project != self.project

        super
      end

      private

      def after_project_change
        return super unless current_journal && RedmineParentChildFilters.journal_subtask_moves?

        previous = Thread.current[MOVER]
        begin
          # Subtasks of subtasks are moved by the subtask's own
          # after_project_change, whose journal is the one set up here, so the
          # same user is passed all the way down.
          Thread.current[MOVER] = current_journal.user
          super
        ensure
          Thread.current[MOVER] = previous
        end
      end
    end
  end
end

Issue.prepend(RedmineParentChildFilters::Patches::SubtaskMoveJournalPatch)
