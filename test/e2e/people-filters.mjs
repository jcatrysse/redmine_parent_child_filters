// "Assignee, author or watcher", "Mentioned or linked" and "Assignee, author,
// watcher, mentioned or linked". Watchers stay behind view_issue_watchers,
// private notes behind view_private_notes.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const P = 'e2e-project';
const t = await e2e('people-filters');

// Principal ids, read as admin.
await t.login('admin');
const users = {};
for (const login of ['admin', 'manager', 'reporter']) {
  const { body } = await pcf.api(t, `/users.json?name=${login}`);
  users[login] = String(body.users.find(u => u.login === login).id);
}

await t.login('manager');
await pcf.filtered(t, 'involved-reporter-as-manager', 'As manager: "Assignee, author or watcher" is reporter: the subtask assigned to reporter and the issue reporter watches.',
  P, [['involved_id', '=', [users.reporter]]], { include: ['PCF Watched'], exclude: ['PCF Mention', 'PCF Standalone'] });

await pcf.filtered(t, 'mentioned-reporter', 'As manager: "Mentioned or linked" is reporter: "@reporter" in the description of PCF Mention.',
  P, [['mentioned_id', '=', [users.reporter]]], { exact: ['PCF Mention'] });

await pcf.filtered(t, 'mentioned-manager-link', 'As manager: "Mentioned or linked" is manager: "user#<id>" in a note counts as a link.',
  P, [['mentioned_id', '=', [users.manager]]], { exact: ['PCF Mention'] });

await pcf.filtered(t, 'mentioned-private-note-manager', 'As manager (may see private notes): "Mentioned or linked" is admin finds PCF Mention through the private note.',
  P, [['mentioned_id', '=', [users.admin]]], { exact: ['PCF Mention'] });

await pcf.filtered(t, 'involved-or-mentioned', 'As manager: "Assignee, author, watcher, mentioned or linked" is reporter: watched, mentioned and assigned issues together.',
  P, [['involved_or_mentioned_id', '=', [users.reporter]]], { include: ['PCF Watched', 'PCF Mention'], exclude: ['PCF Standalone', 'PCF Dated'] });

await t.login('reporter');
await pcf.filtered(t, 'involved-me', 'As reporter: "Assignee, author or watcher" is << me >>: the issue reporter watches.',
  P, [['involved_id', '=', ['me']]], { include: ['PCF Watched'], exclude: ['PCF Mention', 'PCF Standalone'] });
const subtask = await t.page.locator('table.issues td.subject', { hasText: 'E2E subtask' }).count();
if (!subtask) t.problems.push('involved me as reporter: the subtask assigned to reporter is missing');

await pcf.filtered(t, 'involved-not-me', 'As reporter: "Assignee, author or watcher" is not << me >>: the watched issue is gone, the others remain.',
  P, [['involved_id', '!', ['me']]], { include: ['PCF Standalone'], exclude: ['PCF Watched'] });

// Failure paths: what the reporter is not allowed to see does not count.
await pcf.filtered(t, 'involved-manager-as-reporter', 'As reporter (no "View watchers list"): "Assignee, author or watcher" is manager does not reveal that manager watches PCF Watched.',
  P, [['involved_id', '=', [users.manager]]], { exclude: ['PCF Watched'] });

await pcf.filtered(t, 'mentioned-private-note-reporter', 'As reporter (no "View private notes"): "Mentioned or linked" is admin finds nothing; the only mention is in a private note.',
  P, [['mentioned_id', '=', [users.admin]]], { exact: [] });

await pcf.filtered(t, 'mentioned-reporter-me', 'As reporter: "Mentioned or linked" is << me >>: the description mention is public, so reporter finds it.',
  P, [['mentioned_id', '=', ['me']]], { exact: ['PCF Mention'] });

await pcf.filtered(t, 'mentioned-garbage', 'Failure path: "Mentioned or linked" with a value that is no user ("x\' OR 1=1"): the page answers normally, no PCF issue.',
  P, [['mentioned_id', '=', ["x' OR 1=1"]]], { exact: [] });

await t.done();
