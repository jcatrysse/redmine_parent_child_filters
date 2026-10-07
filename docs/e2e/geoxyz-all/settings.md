# settings

Run 2026-10-07T16:51:16.682Z against http://127.0.0.1:3070.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](settings-page.png) | admin | `/settings/plugin/redmine_parent_child_filters` | The settings page as admin: 26 switches in five groups and the depth bounds with their effective range. |
| ![](settings-root-off.png) | admin | `/settings/plugin/redmine_parent_child_filters` | Root unticked and saved: Redmine confirms the update and the box stays off. |
| ![](settings-root-off-url.png) | manager | `/projects/e2e-project/issues?set_filter=1&sort=id&per_page=100&c%5B%5D=tracker&c%5B%5D=status&c%5B%5D=subject&c%5B%5D=project&f%5B%5D=&f%5B%5D=root_id&op%5Broot_id%5D=%3D&v%5Broot_id%5D%5B%5D=7` | With Root switched off, a URL still asking for Root = #7 answers normally; the filter is ignored, so the list is not narrowed to the epic's tree. Result: PCF Browser child, PCF Browser parent, PCF Dated, PCF Epic, PCF Mention, PCF Parent of hidden, PCF Silent child, PCF Silent parent, PCF Standalone, PCF Story, PCF Task closed, PCF Task open, PCF Watched. |
| ![](settings-depth-reversed.png) | admin | `/settings/plugin/redmine_parent_child_filters` | Minimum 3 and maximum 2 saved: the page states the effective range the filters use ("1 = Parent task · 3–3"), the minimum wins. |
| ![](settings-depth-values.png) | manager | `/projects/e2e-project/issues` | The level filter now offers level 3 only ((3) Bug, (3) Feature, (3) Support); Root is back in the dropdown. |
| ![](settings-restored.png) | admin | `/settings/plugin/redmine_parent_child_filters` | Defaults restored: every filter on, levels 1–5. |
| ![](settings-manager-refused.png) | manager | `/settings/plugin/redmine_parent_child_filters` | Manager (every project permission, not an administrator) is refused the settings page: 403. |
| ![](settings-reporter-refused.png) | reporter | `/settings/plugin/redmine_parent_child_filters` | Reporter is refused the settings page: 403. |
| ![](settings-anonymous-login.png) | anonymous | `/login?back_url=http%3A%2F%2F127.0.0.1%3A3070%2Fsettings%2Fplugin%2Fredmine_parent_child_filters` | Anonymous is sent to the login page. |
| ![](settings-post-refused.png) | admin | `/settings/plugin/redmine_parent_child_filters` | A POST to the settings as manager, with a valid CSRF token, is refused (HTTP 403); as admin, Root is still on. |
