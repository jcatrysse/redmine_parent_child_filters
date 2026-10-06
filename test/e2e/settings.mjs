// The plugin's settings page: switching a filter off, the depth bounds and
// their normalisation, and who may open the page at all.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const SETTINGS = '/settings/plugin/redmine_parent_child_filters';
const t = await e2e('settings');

async function save(step) {
  await t.page.click('#settings form input[type=submit], form[action*="/settings/plugin/"] input[type=submit]');
  await t.settle();
  await t.sudo();
  t.check(step);
  if (!(await t.page.locator('#flash_notice').count())) t.problems.push(`${step}: no "Successful update" notice`);
}

async function dropdown() {
  return t.page.locator('#add_filter_select option').evaluateAll(os => os.map(o => o.value));
}

await t.login('admin');
await t.go(SETTINGS);
await t.sudo();
const boxes = await t.page.locator('input[type=checkbox][name^="settings["]').count();
if (boxes !== 26) t.problems.push(`settings page shows ${boxes} checkboxes, expected 26`);
await t.shot('page', `The settings page as admin: ${boxes} switches in five groups and the depth bounds with their effective range.`);

// Switch the Root filter off.
await t.page.uncheck('#settings_enable_root_id_filter');
await save('switch root off');
if (await t.page.isChecked('#settings_enable_root_id_filter')) t.problems.push('Root is still ticked after saving');
await t.shot('root-off', 'Root unticked and saved: Redmine confirms the update and the box stays off.', { full: false });

await t.login('manager');
await t.go(`/projects/${P}/issues`);
const without = await dropdown();
if (without.includes('root_id')) t.problems.push('Root is still offered after switching it off');
if (!without.includes('root_tracker_id')) t.problems.push('Root: Tracker disappeared with Root');
const epic = await pcf.issueId(t, 'PCF Epic');
// A saved query or a bookmark that still carries the filter is not an error: Redmine drops the unknown filter.
await pcf.filtered(t, 'root-off-url', `With Root switched off, a URL still asking for Root = #${epic} answers normally; the filter is ignored, so the list is not narrowed to the epic's tree.`,
  P, [['root_id', '=', [String(epic)]]], { include: ['PCF Epic', 'PCF Standalone'] });

// Depth bounds, reversed on purpose: minimum 3, maximum 2.
await t.login('admin');
await t.go(SETTINGS);
await t.sudo();
await t.page.check('#settings_enable_root_id_filter');
await t.page.selectOption('#settings_min_depth', '3');
await t.page.selectOption('#settings_max_depth', '2');
await save('reversed depth');
const range = (await t.page.locator('em.info', { hasText: '1 =' }).innerText()).trim();
if (!range.includes('3–3')) t.problems.push(`effective range shows "${range}", expected 3–3`);
await t.shot('depth-reversed', `Minimum 3 and maximum 2 saved: the page states the effective range the filters use ("${range}"), the minimum wins.`);

await t.login('manager');
await t.go(`/projects/${P}/issues`);
if (!(await dropdown()).includes('root_id')) t.problems.push('Root not back after ticking it again');
await t.page.selectOption('#add_filter_select', 'a_specific_parent_tracker_id');
const levels = await t.page.locator('#tr_a_specific_parent_tracker_id select.value option').allInnerTexts();
if (levels.some(l => !l.startsWith('(3)'))) t.problems.push(`depth values not limited to level 3: ${levels.join(', ')}`);
await t.shot('depth-values', `The level filter now offers level 3 only (${levels.join(', ')}); Root is back in the dropdown.`, { full: false });

// Restore the defaults.
await t.login('admin');
await t.go(SETTINGS);
await t.sudo();
await t.page.selectOption('#settings_min_depth', '1');
await t.page.selectOption('#settings_max_depth', '5');
await save('restore depth');
await t.shot('restored', 'Defaults restored: every filter on, levels 1–5.');

// Failure paths: nobody but an administrator reaches the page.
await t.login('manager');
await t.go(SETTINGS, { status: 403 });
await t.shot('manager-refused', 'Manager (every project permission, not an administrator) is refused the settings page: 403.', { full: false });

await t.login('reporter');
await t.go(SETTINGS, { status: 403 });
await t.shot('reporter-refused', 'Reporter is refused the settings page: 403.', { full: false });

await t.anonymous();
await t.go(SETTINGS);
if (!new URL(t.page.url()).pathname.startsWith('/login')) t.problems.push(`anonymous was not sent to the login page: ${t.page.url()}`);
await t.shot('anonymous-login', 'Anonymous is sent to the login page.', { full: false });

// A POST without being admin changes nothing.
await t.login('manager');
const res = await t.page.request.post(`${t.BASE}${SETTINGS}`, { form: { 'settings[enable_root_id_filter]': '0' }, maxRedirects: 0 });
if (![403, 422].includes(res.status())) t.problems.push(`POST as manager answered ${res.status()}, expected 403 or 422`);
await t.login('admin');
await t.go(SETTINGS);
await t.sudo();
if (!(await t.page.isChecked('#settings_enable_root_id_filter'))) t.problems.push('a POST by manager switched Root off');
await t.shot('post-refused', `A POST to the settings as manager is refused (HTTP ${res.status()}); as admin, Root is still on.`, { full: false });

await t.done();
