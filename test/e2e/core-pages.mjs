// Jan, 2026-10-07: with all GEOxyz plugins installed, Project > Settings, the
// issue list and an issue page must answer 200 (a mix of alias_method and
// prepend on one core method made Project > Settings answer 500). Run in the
// combination as well as alone; the issue list carries the plugin's filters.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const t = await e2e('core-pages');

await t.login('admin');
const issue = await pcf.issueId(t, 'PCF Story');
const plugins = (await t.page.request.get(`${t.BASE}/admin/plugins`)).ok()
  ? await (async () => { await t.go('/admin/plugins'); return t.page.locator('table.plugins tr td.name, table.list tr td.name').count(); })()
  : 0;
await t.shot('plugins', `Administration > Plugins: ${plugins} plugin(s) installed in this run.`);

for (const user of ['admin', 'manager']) {
  if (user !== 'admin') await t.login(user);
  await t.go(`/projects/${P}/settings`);
  await t.shot(`settings-${user}`, `Project > Settings as ${user}: 200.`, { full: false });
  await t.go(pcf.filterPath(P, [['child_status_id', '!*'], ['parent_tracker_id', '=', ['2']]]));
  await t.shot(`issues-${user}`, `Issue list as ${user} with two of the plugin's filters (Subtasks: Status none, Parent task: Tracker is Feature): 200.`, { full: false });
  await t.go(`/issues/${issue}`);
  await t.shot(`issue-${user}`, `Issue page of PCF Story as ${user}: 200.`, { full: false });
}

await t.login('reporter');
await t.go(`/projects/${P}/settings`, { status: 403 });
await t.shot('settings-reporter', 'Project > Settings as reporter (no "Manage project"): 403, refused rather than broken.', { full: false });
await t.go(`/issues/${issue}`);
await t.shot('issue-reporter', 'Issue page as reporter: 200.', { full: false });

await t.login('outsider');
await t.go('/projects/e2e-private/settings', { status: 403 });
await t.shot('settings-outsider', 'Project > Settings of the private project as outsider: 403.', { full: false });

await t.done();
