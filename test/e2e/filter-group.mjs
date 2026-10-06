// The plugin's filters are offered in their own group of the "Add filter"
// dropdown, for every user who may see the issue list, and the people and
// project filters sit with Redmine's own groups.
import { e2e } from '../../.codex/e2e/lib.mjs';

const P = 'e2e-project';
const GROUP = 'Parent and child';
const t = await e2e('filter-group');

async function groupOptions() {
  return t.page.locator(`#add_filter_select optgroup[label="${GROUP}"] option`).allInnerTexts();
}

for (const user of ['manager', 'reporter', 'outsider']) {
  await t.login(user);
  await t.go(`/projects/${P}/issues`);
  const options = await groupOptions();
  if (options.length !== 20) t.problems.push(`${user}: ${options.length} options in "${GROUP}", expected 20`);
  for (const label of ['Root: Tracker', 'Subtasks (any): Status', 'Has a parent or a subtask', 'Parent task (level): Tracker']) {
    if (!options.includes(label)) t.problems.push(`${user}: "${label}" missing from the group`);
  }
  // The people and project filters are not in the hierarchy group.
  const all = await t.page.locator('#add_filter_select option').allInnerTexts();
  for (const label of ['Assignee, author or watcher', 'Mentioned or linked', 'Project (History)', 'Project (Original)']) {
    if (!all.includes(label)) t.problems.push(`${user}: "${label}" missing from the dropdown`);
    if (options.includes(label)) t.problems.push(`${user}: "${label}" is in the hierarchy group`);
  }
  // Expand the list so the screenshot shows the group (a <select> does not open in a headless screenshot).
  await t.page.evaluate(g => {
    const sel = document.querySelector('#add_filter_select');
    const og = sel && [...sel.querySelectorAll('optgroup')].find(o => o.label === g);
    if (!og) return;
    const box = document.createElement('div');
    box.id = 'pcf-e2e-group';
    box.style.cssText = 'border:2px solid #628db6;padding:6px;margin:6px 0;background:#fff';
    box.innerHTML = '<strong>' + g + '</strong> (contents of the dropdown group): ' + [...og.children].map(o => o.textContent).join(' | ');
    sel.parentNode.insertBefore(box, sel.nextSibling);
  }, GROUP);
  await t.shot(`dropdown-${user}`, `As ${user}: the "Add filter" dropdown carries the plugin's ${options.length} hierarchy filters in their own group "${GROUP}"; people and project filters are in Redmine's groups.`, { full: false });
}

// Picking a filter from the group adds its row with the values to choose from (Redmine 7 JavaScript).
await t.login('manager');
await t.go(`/projects/${P}/issues`);
await t.page.selectOption('#add_filter_select', 'a_specific_parent_tracker_id');
await t.page.waitForSelector('#tr_a_specific_parent_tracker_id', { timeout: 5000 }).catch(() => t.problems.push('picking the filter added no row'));
const values = await t.page.locator('#tr_a_specific_parent_tracker_id select.value option').allInnerTexts();
for (const v of ['(1) Bug', '(2) Feature', '(5) Support']) if (!values.includes(v)) t.problems.push(`depth values: "${v}" missing, got ${values.join(', ')}`);
if (values.some(v => v.startsWith('(6)'))) t.problems.push('depth values go beyond the configured maximum of 5');
await t.page.selectOption('#add_filter_select', 'root_id');
await t.page.selectOption('#add_filter_select', 'tree_has_parent_or_child');
t.check('add filter rows');
await t.shot('rows-added', `Picking "Parent task (level): Tracker", "Root" and "Has a parent or a subtask" adds their rows; the level filter offers (1)..(5) per tracker (${values.length} values).`, { full: false });

// Anonymous on a public project: same list, no error.
await t.anonymous();
await t.go(`/projects/${P}/issues`);
const anon = await groupOptions();
if (anon.length !== 20) t.problems.push(`anonymous: ${anon.length} options in "${GROUP}", expected 20`);
await t.shot('dropdown-anonymous', `Anonymous on a public project: the issue list renders with the plugin's group (${anon.length} filters).`, { full: false });

// Failure path: the private project stays refused to a non-member, filters or not.
await t.login('outsider');
await t.go('/projects/e2e-private/issues?set_filter=1&f[]=child_tracker_id&op[child_tracker_id]=*', { status: 403 });
await t.shot('private-refused', 'A non-member asking for the private project\'s issue list with a plugin filter is refused (403).', { full: false });

await t.done();
