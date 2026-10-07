# subtask-move-journal

Run 2026-10-07T16:57:35.347Z against http://127.0.0.1:3070.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](subtask-move-journal-edit-form.png) | manager | `/issues/17/edit` | Manager moves PCF Browser parent to E2E history on the issue form. |
| ![](subtask-move-journal-child-history.png) | manager | `/issues/18?tab=history` | PCF Browser child moved along to E2E history; its history now says "Project changed from E2E project to E2E history", by Manager E2E. |
| ![](subtask-move-journal-parent-history.png) | manager | `/issues/17?tab=history` | The parent's own move, journaled by Redmine as always. Mail: one notification about the parent, none about the child. |
| ![](subtask-move-journal-setting-off.png) | admin | `/settings/plugin/redmine_parent_child_filters` | Admin unticks "Record subtasks moved along with their parent in their history" (Projects group). |
| ![](subtask-move-journal-silent-edit.png) | manager | `/issues/19/edit` | With the journaling off, manager moves PCF Silent parent to E2E history. |
| ![](subtask-move-journal-silent-child-history.png) | manager | `/issues/20?tab=history` | Setting off: PCF Silent child moved along to E2E history, and its history has no new entry (0 project moves, as before). |
| ![](subtask-move-journal-setting-on.png) | admin | `/settings/plugin/redmine_parent_child_filters` | The journaling is switched back on (the default), Projects group. |
| ![](subtask-move-journal-reporter-no-move.png) | reporter | `/issues/18/edit` | Reporter (Reporter role, no "Edit issues") gets the notes-only form: no Project field, so no move. |

## Problems

- /issues/18/edit as reporter: HTTP 403, expected 200
