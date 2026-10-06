// Subtasks and Subtasks (any), on tracker and status. A subtask in a project the
// user cannot see does not exist for that user.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const t = await e2e('child-filters');

await t.login('manager');

await pcf.filtered(t, 'child-tracker', 'As manager (member of the private project): Subtasks: Tracker is Bug includes "PCF Parent of hidden", whose Bug subtask lives in e2e-private.',
  P, [['child_tracker_id', '=', ['1']]],
  { include: ['PCF Story', 'PCF Parent of hidden'], exclude: ['PCF Epic', 'PCF Task open', 'PCF Standalone'] });

await pcf.filtered(t, 'child-pair', 'Subtasks: Tracker is Bug AND Subtasks: Status is Closed describe one subtask: only the story, which has a closed Bug.',
  P, [['child_tracker_id', '=', ['1']], ['child_status_id', '=', ['5']]], { exact: ['PCF Story'] });

await pcf.filtered(t, 'child-tracker-not', 'Subtasks: Tracker is not Bug means "has no Bug subtask": the story is out, the epic (Support child) and standalone issues are in.',
  P, [['child_tracker_id', '!', ['1']]],
  { include: ['PCF Epic', 'PCF Standalone', 'PCF Task open'], exclude: ['PCF Story', 'PCF Parent of hidden'] });

await pcf.filtered(t, 'a-child-tracker', 'Subtasks (any): Tracker is Bug: the epic too, its Bug tasks are two levels down.',
  P, [['a_child_tracker_id', '=', ['1']]],
  { include: ['PCF Epic', 'PCF Story', 'PCF Parent of hidden'], exclude: ['PCF Standalone', 'PCF Task open'] });

await pcf.filtered(t, 'a-child-status', 'Subtasks (any): Status is Closed: the epic and the story, which have the closed task below them.',
  P, [['a_child_status_id', '=', ['5']]], { exact: ['PCF Epic', 'PCF Story'] });

await pcf.filtered(t, 'child-any', 'Subtasks: Status any = "has a subtask", as manager.',
  P, [['child_status_id', '*']],
  { include: ['PCF Epic', 'PCF Story', 'PCF Parent of hidden'], exclude: ['PCF Standalone', 'PCF Task open'] });

// Without access to the private project the hidden subtask does not exist.
await t.login('reporter');
await pcf.filtered(t, 'child-tracker-reporter', 'As reporter (no access to e2e-private): Subtasks: Tracker is Bug leaves "PCF Parent of hidden" out; its only subtask is invisible.',
  P, [['child_tracker_id', '=', ['1']]],
  { include: ['PCF Story'], exclude: ['PCF Parent of hidden'] });

await pcf.filtered(t, 'child-any-reporter', 'As reporter: Subtasks: Status any leaves "PCF Parent of hidden" out.',
  P, [['child_status_id', '*']], { include: ['PCF Epic', 'PCF Story'], exclude: ['PCF Parent of hidden'] });

await pcf.filtered(t, 'child-none-reporter', 'As reporter: Subtasks: Status none (operator !* from the URL; Redmine\'s status filter type does not offer "none" in the dropdown, so the operator box shows its first entry) includes "PCF Parent of hidden": no subtask as far as the reporter can see.',
  P, [['child_status_id', '!*']], { include: ['PCF Parent of hidden', 'PCF Standalone'], exclude: ['PCF Epic', 'PCF Story'] });

// The hidden subtask must not leak through the list either.
await t.go(pcf.filterPath(null, [['a_child_tracker_id', '*']]));
const all = await pcf.subjects(t.page);
if (all.includes('PCF Hidden child')) t.problems.push('reporter sees PCF Hidden child on the cross-project list');
await t.shot('cross-project-reporter', `As reporter, all projects, Subtasks (any) any: the private subtask is not listed. PCF issues: ${all.join(', ')}.`);

await t.done();
