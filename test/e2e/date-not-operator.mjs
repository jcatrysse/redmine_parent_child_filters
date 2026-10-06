// The "is not" operator the plugin adds to date filters.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const t = await e2e('date-not-operator');

await t.login('manager');
await t.go(`/projects/${P}/issues`);
await t.page.selectOption('#add_filter_select', 'start_date');
const ops = await t.page.locator('#operators_start_date option').allInnerTexts();
if (!ops.includes('is not')) t.problems.push(`start date operators lack "is not": ${ops.join(', ')}`);
await t.page.selectOption('#operators_start_date', '!');
t.check('pick operator');
await t.shot('operator-offered', `Start date offers "is not" (${ops.join(', ')}).`, { full: false });

await pcf.filtered(t, 'is', 'Start date is 2026-01-15: PCF Dated only.',
  P, [['start_date', '=', ['2026-01-15']]], { exact: ['PCF Dated'] });

await pcf.filtered(t, 'is-not', 'Start date is not 2026-01-15: everything else, PCF Dated left out.',
  P, [['start_date', '!', ['2026-01-15']]], { include: ['PCF Standalone', 'PCF Epic'], exclude: ['PCF Dated'] });

await pcf.filtered(t, 'due-is-not', 'Due date is not 2026-01-15 on issues without a due date: they all stay (no due date is not that date).',
  P, [['due_date', '!', ['2026-01-15']]], { include: ['PCF Dated', 'PCF Standalone'] });

// Failure path: an invalid date is refused by Redmine's own validation, shown as an error.
await t.go(pcf.filterPath(P, [['start_date', '!', ['not-a-date']]]));
const error = await t.page.locator('#errorExplanation').count();
if (!error) t.problems.push('an invalid date was not refused');
await t.shot('invalid-date', 'Start date is not "not-a-date": Redmine refuses the filter with its validation message, no server error.');

await t.done();
