// With redmine_issue_field_visibility installed (the GEOxyz combination), a
// role from which the assignee and the description are hidden cannot get them
// back through the people filters. Without that plugin this scenario only
// records that it was skipped.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const IFV = '/settings/plugin/redmine_issue_field_visibility';
const t = await e2e('hidden-fields');

await t.login('admin');
const probe = await t.page.request.get(t.BASE + IFV, { maxRedirects: 0 });
if (probe.status() === 404) {
  await t.go('/admin/plugins');
  await t.shot('skipped', 'redmine_issue_field_visibility is not installed here: nothing to combine with, scenario skipped.');
  await t.done();
  process.exit();
}

const users = {};
for (const login of ['manager', 'reporter']) {
  users[login] = String((await pcf.api(t, `/users.json?name=${login}`)).body.users.find(u => u.login === login).id);
}

async function hideForReporter(hide) {
  await t.login('admin');
  await t.go(IFV);
  await t.sudo();
  for (const field of ['assigned_to_id', 'description']) {
    const box = t.page.locator(`input[type=checkbox][name$="[${field}]"][name^="settings[hiddenfields][${await reporterRoleId()}]"]`);
    if (hide) await box.check(); else await box.uncheck();
  }
  await t.page.click('form[action*="/settings/plugin/"] input[type=submit]');
  await t.settle();
  await t.sudo();
  t.check(hide ? 'hide fields' : 'show fields');
}

let roleIdCache;
async function reporterRoleId() {
  if (!roleIdCache) {
    const roles = (await pcf.api(t, '/roles.json')).body.roles;
    roleIdCache = String(roles.find(r => r.name === 'Reporter').id);
  }
  return roleIdCache;
}

// Before: reporter finds the issue assigned to manager, and the mention in a description.
await t.login('reporter');
await pcf.filtered(t, 'before-involved', 'Fields visible: as reporter, "Assignee, author or watcher" is manager finds "E2E assigned issue" (assigned to manager).',
  P, [['involved_id', '=', [users.manager]]], { exclude: [] });
const before = await t.page.locator('table.issues td.subject', { hasText: 'E2E assigned issue' }).count();
if (!before) t.problems.push('before hiding: E2E assigned issue not found through the assignee');

await hideForReporter(true);
await t.shot('ifv-settings', 'redmine_issue_field_visibility: Assignee and Description hidden from the Reporter role.');

await t.login('reporter');
await t.go(`/projects/${P}/issues`);
const offered = await t.page.locator('#add_filter_select option').evaluateAll(os => os.map(o => o.value));
if (offered.includes('assigned_to_id')) t.problems.push('the Assignee filter is still offered to reporter');
if (!offered.includes('involved_id')) t.problems.push('"Assignee, author or watcher" disappeared');
await pcf.filtered(t, 'after-involved', 'Assignee hidden: as reporter, "Assignee, author or watcher" is manager no longer finds "E2E assigned issue"; the assignee cannot be read back through this filter.',
  P, [['involved_id', '=', [users.manager]]], {});
if (await t.page.locator('table.issues td.subject', { hasText: 'E2E assigned issue' }).count()) {
  t.problems.push('after hiding: E2E assigned issue still found through the assignee');
}
await pcf.filtered(t, 'after-mention', 'Description hidden: as reporter, "Mentioned or linked" is << me >> no longer finds PCF Mention, whose mention is in the description.',
  P, [['mentioned_id', '=', ['me']]], { exclude: ['PCF Mention'] });

// Manager has another role, from which nothing is hidden: unchanged.
await t.login('manager');
await pcf.filtered(t, 'manager-unchanged', 'Manager (role E2E full, nothing hidden): "Mentioned or linked" is reporter still finds PCF Mention.',
  P, [['mentioned_id', '=', [users.reporter]]], { include: ['PCF Mention'] });

await hideForReporter(false);
await t.login('reporter');
await pcf.filtered(t, 'restored', 'Fields shown again: as reporter, "Mentioned or linked" is << me >> finds PCF Mention again.',
  P, [['mentioned_id', '=', ['me']]], { include: ['PCF Mention'] });

await t.done();
