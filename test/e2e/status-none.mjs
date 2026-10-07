// Jan, 2026-10-07: "none" in the dropdown of the status filters whose relative
// may be missing. Picked through the form, applied, and checked against what
// "none" means: no such relative, as far as the user can see.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const WITH_NONE = ['parent_status_id', 'a_parent_status_id', 'child_status_id', 'a_child_status_id',
  'tree_parent_status_id', 'tree_child_status_id'];
const t = await e2e('status-none');

async function operators(field) {
  await t.page.selectOption('#add_filter_select', field);
  await t.page.waitForSelector(`#operators_${field} option`, { state: 'attached', timeout: 10000 })
    .catch(() => t.problems.push(`picking ${field} added no row`));
  return t.page.locator(`#operators_${field} option`).evaluateAll(os => os.map(o => o.value));
}

// Shows the operators of a closed select next to it, for the screenshot.
async function showOperators(field, list) {
  await t.page.evaluate(([f, l]) => {
    const box = document.createElement('div');
    box.style.cssText = 'border:2px solid #628db6;padding:6px;margin:6px 0;background:#fff';
    box.textContent = `Operators offered for ${f}: ` + l.join(' | ');
    document.querySelector('#content').prepend(box);
  }, [field, list]);
}

// Picks Subtasks: Status, chooses none in the form and applies it.
async function applyNoneThroughTheForm() {
  await t.go(`/projects/${P}/issues?set_filter=1&f[]=&per_page=100&sort=id&c[]=tracker&c[]=status&c[]=subject`);
  await operators('child_status_id');
  await t.page.selectOption('#operators_child_status_id', '!*');
  if (await t.page.locator('#values_child_status_id_1').isVisible()) t.problems.push('none still shows a value list');
  await t.page.click('#query_form a.icon-checked, #query_form a[onclick*="submit"]');
  await t.settle();
  t.check('apply none');
  const selected = await t.page.locator('#operators_child_status_id').inputValue().catch(() => '');
  if (selected !== '!*') t.problems.push(`after applying, the operator box shows "${selected}", expected none`);
}

for (const user of ['admin', 'manager', 'reporter', 'outsider']) {
  await t.login(user);
  await t.go(`/projects/${P}/issues`);
  const missing = [];
  for (const field of WITH_NONE) {
    const ops = await operators(field);
    if (!ops.includes('!*')) missing.push(field);
    if (!ops.includes('*') || !ops.includes('o') || !ops.includes('c')) t.problems.push(`${user}: ${field} lost Redmine's status operators: ${ops.join(',')}`);
  }
  if (missing.length) t.problems.push(`${user}: no "none" on ${missing.join(', ')}`);
  if (user === 'manager') {
    const labels = await t.page.locator('#operators_child_status_id option').evaluateAll(os => os.map(o => o.textContent.trim()));
    await showOperators('Subtasks: Status', labels);
    await t.shot('rows-manager', `As manager: the six status filters of a relative that may be missing, picked from the dropdown, each offer "none" (Subtasks: Status: ${labels.join(', ')}).`);
  }
  // Redmine's own status filter and the root and tree status filters do not.
  for (const field of ['status_id', 'root_status_id', 'tree_status_id']) {
    const ops = field === 'status_id'
      ? await t.page.locator('#operators_status_id option').evaluateAll(os => os.map(o => o.value))
      : await operators(field);
    if (ops.includes('!*')) t.problems.push(`${user}: ${field} offers none`);
  }
  if (user !== 'manager') {
    await t.shot(`rows-${user}`, `As ${user}: the same six filters offer "none"; Status, Root: Status and Tree: Status do not.`, { full: false });
  }
}

// Applied through the form: none = no subtask.
await t.login('manager');
await applyNoneThroughTheForm();
let got = await pcf.expectSubjects(t, 'none-manager', {
  include: ['PCF Standalone', 'PCF Task open', 'PCF Task closed'],
  exclude: ['PCF Epic', 'PCF Story', 'PCF Parent of hidden'] });
await t.shot('applied-manager', `As manager, Subtasks: Status "none" chosen in the form and applied: issues without a subtask. "PCF Parent of hidden" is out, its subtask in the private project is visible to manager. Result: ${got.join(', ')}.`);

await t.login('reporter');
await applyNoneThroughTheForm();
got = await pcf.expectSubjects(t, 'none-reporter', {
  include: ['PCF Standalone', 'PCF Parent of hidden'], exclude: ['PCF Epic', 'PCF Story'] });
await t.shot('applied-reporter', `As reporter (no access to the private project): "PCF Parent of hidden" is in, its only subtask is invisible. Result: ${got.join(', ')}.`);

// any and none split the list.
await t.login('manager');
await pcf.filtered(t, 'parent-none', 'Parent task: Status "none" (top level issues): the epic and the standalone issues, not the story or the tasks.',
  P, [['parent_status_id', '!*']], { include: ['PCF Epic', 'PCF Standalone'], exclude: ['PCF Story', 'PCF Task open'] });
await pcf.filtered(t, 'tree-child-none', 'Tree / Subtasks: Status "none": issues in no tree with a subtask, i.e. the standalone ones.',
  P, [['tree_child_status_id', '!*']], { include: ['PCF Standalone'], exclude: ['PCF Epic', 'PCF Task open'] });

// Saved as a query: the operator comes back in the form.
await t.go(`/projects/${P}/queries/new?set_filter=1&f[]=child_status_id&op[child_status_id]=!*`);
await t.page.fill('#query_name', `PCF none ${Date.now()}`);
await t.page.click('#query-form input[type=submit], form#query-form input[name=commit], #query_form input[type=submit]');
await t.settle();
t.check('save query');
// A saved query opens with its filters folded; unfold them for the picture.
if (!(await t.page.locator('#operators_child_status_id').isVisible())) {
  await t.page.locator('fieldset#filters legend, legend:has-text("Filters")').first().click().catch(() => {});
}
const saved = await t.page.locator('#operators_child_status_id').inputValue().catch(() => '');
if (!(await t.page.locator('#operators_child_status_id').isVisible())) t.problems.push('saved query: the filter row is not shown');
if (saved !== '!*') t.problems.push(`saved query shows operator "${saved}", expected none`);
await t.shot('saved-query', `A query saved with Subtasks: Status "none" opens with "none" selected (operator box: ${saved}).`);

// Refusal: the private project stays closed to a non-member, with the operator or without.
await t.login('outsider');
await t.go('/projects/e2e-private/issues?set_filter=1&f[]=child_status_id&op[child_status_id]=!*', { status: 403 });
await t.shot('private-refused', 'Outsider asking the private project with Subtasks: Status "none": 403.', { full: false });

await t.done();
