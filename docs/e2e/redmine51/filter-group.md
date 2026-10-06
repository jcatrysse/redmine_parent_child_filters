# filter-group

Run 2026-10-06T20:15:41.230Z against http://127.0.0.1:3051.

| screenshot | user | URL | shows |
|---|---|---|---|
| `filter-group-dropdown-manager.png` | manager | `/projects/e2e-project/issues` | As manager: the "Add filter" dropdown carries the plugin's 20 hierarchy filters in their own group "Parent and child"; people and project filters are in Redmine's groups. |
| `filter-group-dropdown-reporter.png` | reporter | `/projects/e2e-project/issues` | As reporter: the "Add filter" dropdown carries the plugin's 20 hierarchy filters in their own group "Parent and child"; people and project filters are in Redmine's groups. |
| `filter-group-dropdown-outsider.png` | outsider | `/projects/e2e-project/issues` | As outsider: the "Add filter" dropdown carries the plugin's 20 hierarchy filters in their own group "Parent and child"; people and project filters are in Redmine's groups. |
| `filter-group-rows-added.png` | manager | `/projects/e2e-project/issues` | Picking "Parent task (level): Tracker", "Root" and "Has a parent or a subtask" adds their rows; the level filter offers (1)..(5) per tracker (15 values). |
| `filter-group-dropdown-anonymous.png` | anonymous | `/projects/e2e-project/issues` | Anonymous on a public project: the issue list renders with the plugin's group (20 filters). |
| `filter-group-private-refused.png` | outsider | `/projects/e2e-private/issues?set_filter=1&f[]=child_tracker_id&op[child_tracker_id]=*` | A non-member asking for the private project's issue list with a plugin filter is refused (403). |
