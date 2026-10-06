// Parent task, Parent task (any) and Parent task (level), on tracker and status,
// with Redmine's status history operator.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const TASKS = ['PCF Task open', 'PCF Task closed'];
const t = await e2e('parent-filters');

await t.login('manager');

await pcf.filtered(t, 'parent-tracker', 'Parent task: Tracker is Support: the two tasks below the Support story, nothing else.',
  P, [['parent_tracker_id', '=', ['3']]], { exact: TASKS });

await pcf.filtered(t, 'parent-status', 'Parent task: Status is In Progress: the tasks of the story that is in progress.',
  P, [['parent_status_id', '=', ['2']]], { exact: TASKS });

await pcf.filtered(t, 'parent-status-has-been', 'Parent task: Status has been In Progress (Redmine\'s history operator on a plugin filter).',
  P, [['parent_status_id', 'ev', ['2']]], { exact: TASKS });

await pcf.filtered(t, 'parent-tracker-not', 'Parent task: Tracker is not Feature: the story (parent is a Feature) is out; issues without a parent are in.',
  P, [['parent_tracker_id', '!', ['2']]],
  { include: ['PCF Epic', 'PCF Standalone', ...TASKS], exclude: ['PCF Story', 'PCF Browser child', 'PCF Silent child'] });

await pcf.filtered(t, 'a-parent-tracker', 'Parent task (any): Tracker is Feature: everything below a Feature at any level.',
  P, [['a_parent_tracker_id', '=', ['2']]],
  { include: ['PCF Story', ...TASKS], exclude: ['PCF Epic', 'PCF Standalone', 'PCF Parent of hidden'] });

await pcf.filtered(t, 'a-parent-pair', 'Parent task (any): Tracker is Feature AND Status is In Progress describe one ancestor: no Feature ancestor is in progress, so nothing matches.',
  P, [['a_parent_tracker_id', '=', ['2']], ['a_parent_status_id', '=', ['2']]], { exact: [] });

await pcf.filtered(t, 'level-tracker', 'Parent task (level): Tracker is "(2) Feature": the grandchildren of the epic only.',
  P, [['a_specific_parent_tracker_id', '=', ['2:2']]], { exact: TASKS });

await pcf.filtered(t, 'level-mixed', 'Parent task (level): Tracker "(1) Feature" or "(2) Feature": each depth on its own, the story and the tasks (the multi-select shows the first selected value).',
  P, [['a_specific_parent_tracker_id', '=', ['2:1', '2:2']]],
  { include: ['PCF Story', ...TASKS], exclude: ['PCF Epic'] });

await pcf.filtered(t, 'level-status', 'Parent task (level): Status is "(1) In Progress": the tasks whose direct parent is in progress.',
  P, [['a_specific_parent_status_id', '=', ['2:1']]], { exact: TASKS });

// Failure paths: a depth outside the configured range or above the hard ceiling,
// and a value that is not "tracker:depth", must never reach SQL as given.
await pcf.filtered(t, 'level-too-deep', 'Parent task (level) "2:99", a depth far above the ceiling of 10, typed into the URL: refused quietly, no PCF issue, no error.',
  P, [['a_specific_parent_tracker_id', '=', ['2:99']]], { exact: [] }, { notAnOption: true });

await pcf.filtered(t, 'level-garbage', 'Parent task (level) "x;DROP": not a tracker and depth; the page answers normally with no PCF issue.',
  P, [['a_specific_parent_tracker_id', '=', ['x;DROP']]], { exact: [] }, { notAnOption: true });

await t.login('reporter');
await pcf.filtered(t, 'parent-tracker-reporter', 'As reporter (core Reporter role): Parent task: Tracker is Support gives the same two tasks.',
  P, [['parent_tracker_id', '=', ['3']]], { exact: TASKS });

await t.done();
