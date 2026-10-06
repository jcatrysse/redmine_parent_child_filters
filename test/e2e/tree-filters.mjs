// The tree filters: whole hierarchies where one member matches, and standalone
// issues that match by themselves.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const EPIC_FAMILY = ['PCF Epic', 'PCF Story', 'PCF Task open', 'PCF Task closed'];
const LONERS = ['PCF Standalone', 'PCF Mention', 'PCF Watched', 'PCF Dated'];
const t = await e2e('tree-filters');

await t.login('manager');

await pcf.filtered(t, 'has-relative-no', 'Has a parent or a subtask: no — the standalone issues only.',
  P, [['tree_has_parent_or_child', '=', ['0']]], { include: LONERS, exclude: [...EPIC_FAMILY, 'PCF Parent of hidden'] });

await pcf.filtered(t, 'has-relative-yes', 'Has a parent or a subtask: yes — every member of a tree, the parent of the hidden subtask included for manager.',
  P, [['tree_has_parent_or_child', '=', ['1']]], { include: [...EPIC_FAMILY, 'PCF Parent of hidden'], exclude: LONERS });

await pcf.filtered(t, 'tree-status-closed', 'Tree: Status is Closed: the whole epic tree, because one of its tasks is closed.',
  P, [['tree_status_id', '=', ['5']]], { include: EPIC_FAMILY, exclude: [...LONERS, 'PCF Parent of hidden'] });

await pcf.filtered(t, 'tree-tracker', 'Tree: Tracker is Support: the epic tree (its story is Support) and the standalone Support issues.',
  P, [['tree_tracker_id', '=', ['3']]], { include: [...EPIC_FAMILY, ...LONERS], exclude: ['PCF Parent of hidden'] });

await pcf.filtered(t, 'tree-parent-tracker', 'Tree / Parent task: Tracker is Support: the trees in which a Support issue is a parent (the epic tree), and, as documented for the tree filters, standalone Support issues; not the Feature-parent trees.',
  P, [['tree_parent_tracker_id', '=', ['3']]], { include: [...EPIC_FAMILY, ...LONERS], exclude: ['PCF Parent of hidden', 'PCF Browser parent', 'PCF Silent parent'] });

await pcf.filtered(t, 'tree-child-status', 'Tree / Subtasks: Status is Closed: the trees in which a subtask is closed: the epic tree.',
  P, [['tree_child_status_id', '=', ['5']]], { include: EPIC_FAMILY, exclude: ['PCF Parent of hidden', ...LONERS] });

await pcf.filtered(t, 'tree-child-tracker', 'Tree / Subtasks: Tracker is Bug, as manager: the epic tree and the parent of the hidden Bug.',
  P, [['tree_child_tracker_id', '=', ['1']]], { include: [...EPIC_FAMILY, 'PCF Parent of hidden'], exclude: LONERS });

await t.login('reporter');
await pcf.filtered(t, 'has-relative-no-reporter', 'As reporter: Has a parent or a subtask: no includes "PCF Parent of hidden", whose only relative is invisible to the reporter.',
  P, [['tree_has_parent_or_child', '=', ['0']]], { include: [...LONERS, 'PCF Parent of hidden'], exclude: EPIC_FAMILY });

await pcf.filtered(t, 'tree-child-tracker-reporter', 'As reporter: Tree / Subtasks: Tracker is Bug leaves the parent of the hidden Bug out.',
  P, [['tree_child_tracker_id', '=', ['1']]], { include: EPIC_FAMILY, exclude: ['PCF Parent of hidden'] });

await pcf.filtered(t, 'invalid-flag', 'Failure path: Has a parent or a subtask = "maybe" from the URL: the page answers normally, no PCF issue.',
  P, [['tree_has_parent_or_child', '=', ['maybe']]], { exact: [] }, { notAnOption: true });

await t.done();
