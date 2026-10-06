// Root, Root: Tracker and Root: Status: issues by the top of their tree.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const EPIC_FAMILY = ['PCF Epic', 'PCF Story', 'PCF Task open', 'PCF Task closed'];
const t = await e2e('root-filters');

await t.login('manager');
const epic = await pcf.issueId(t, 'PCF Epic');

await pcf.filtered(t, 'root-id', `Root is #${epic} (PCF Epic): the epic and every issue below it, nothing else.`,
  P, [['root_id', '=', [String(epic)]]], { exact: EPIC_FAMILY });

await pcf.filtered(t, 'root-tracker', 'Root: Tracker is Feature: every tree whose top is a Feature; a standalone Support issue is left out.',
  P, [['root_tracker_id', '=', ['2']]],
  { include: [...EPIC_FAMILY, 'PCF Parent of hidden'], exclude: ['PCF Standalone', 'PCF Mention'] });

await pcf.filtered(t, 'root-tracker-not', 'Root: Tracker is not Feature: the epic\'s tree is gone, standalone Support issues remain (their own root).',
  P, [['root_tracker_id', '!', ['2']]],
  { include: ['PCF Standalone', 'PCF Mention'], exclude: EPIC_FAMILY });

await pcf.filtered(t, 'root-status', 'Root: Status is New: the epic (New) and its tree, including the closed task.',
  P, [['root_status_id', '=', ['1']]], { include: [...EPIC_FAMILY, 'PCF Standalone'] });

await pcf.filtered(t, 'root-status-closed', 'Root: Status closed: no PCF root is closed, so the list is empty of PCF issues.',
  P, [['root_status_id', 'c']], { exact: [] });

// Failure paths: input the filter cannot use is refused or matches nothing, never a server error.
await pcf.filtered(t, 'root-id-invalid', 'Root is "abc": not an issue id; the page answers normally and lists no PCF issue.',
  P, [['root_id', '=', ['abc']]], { exact: [] });

await pcf.filtered(t, 'root-id-list', `Root is "${epic}, 999999": a list with an id that does not exist still finds the epic's tree.`,
  P, [['root_id', '=', [`${epic}, 999999`]]], { exact: EPIC_FAMILY });

// The same filter as a member without any extra permission: same tree, it is all visible to them.
await t.login('reporter');
await pcf.filtered(t, 'root-id-reporter', `As reporter: Root is #${epic} lists the same tree.`,
  P, [['root_id', '=', [String(epic)]]], { exact: EPIC_FAMILY });

await t.done();
