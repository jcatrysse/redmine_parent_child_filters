// Moving an issue to another project in the browser gives its subtask a
// journal of its own, by the mover and without a mail; switched off, the
// subtask moves silently, as in core Redmine.
import fs from 'node:fs';
import path from 'node:path';
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const SETTINGS = '/settings/plugin/redmine_parent_child_filters';
const MAILS = path.join(process.env.REDMINE_DIR || 'redmine', 'tmp', 'mails');
const t = await e2e('subtask-move-journal');

function mailSizes() {
  if (!fs.existsSync(MAILS)) return {};
  return Object.fromEntries(fs.readdirSync(MAILS).map(f => [f, fs.statSync(path.join(MAILS, f)).size]));
}
function newMail(before) {
  if (!fs.existsSync(MAILS)) return '';
  return fs.readdirSync(MAILS).map(f => fs.readFileSync(path.join(MAILS, f), 'utf8').slice(before[f] || 0)).join('\n');
}

async function issue(id) {
  return (await pcf.api(t, `/issues/${id}.json?include=journals`)).body.issue;
}

function projectMoves(i) {
  return (i.journals || []).filter(j => (j.details || []).some(d => d.name === 'project_id'));
}

async function setJournaling(on, step) {
  await t.login('admin');
  await t.go(SETTINGS);
  await t.sudo();
  if (on) await t.page.check('#settings_journal_subtask_moves'); else await t.page.uncheck('#settings_journal_subtask_moves');
  await t.page.click('form[action*="/settings/plugin/"] input[type=submit]');
  await t.settle();
  await t.sudo();
  t.check(step);
}

// Moves the parent through the issue form to whichever test project it is not in.
async function moveInBrowser(parentId, shotName, caption) {
  const before = await issue(parentId);
  const target = before.project.name === 'E2E project' ? 'E2E history' : 'E2E project';
  await t.go(`/issues/${parentId}/edit`);
  await t.page.selectOption('#issue_project_id', { label: target });
  await t.page.waitForLoadState('networkidle').catch(() => {});
  await t.page.waitForTimeout(500);
  await t.shot(shotName, caption.replace('%TARGET%', target), { full: false });
  await t.page.click('#issue-form input[name=commit]');
  await t.settle();
  t.check(`move ${parentId}`);
  if (await t.page.locator('#errorExplanation').count()) t.problems.push(`moving #${parentId}: ${await t.page.locator('#errorExplanation').innerText()}`);
  return { from: before.project.name, to: target };
}

await t.login('manager');
const parent = await pcf.issueId(t, 'PCF Browser parent');
const child = await pcf.issueId(t, 'PCF Browser child');
const movesBefore = projectMoves(await issue(child)).length;
const mailsBefore = mailSizes();

const move = await moveInBrowser(parent, 'edit-form', `Manager moves PCF Browser parent to %TARGET% on the issue form.`);
await t.page.waitForTimeout(3000); // mail goes out through Active Job
const after = await issue(child);
const moves = projectMoves(after);
if (moves.length !== movesBefore + 1) t.problems.push(`subtask has ${moves.length} project moves, expected ${movesBefore + 1}`);
const last = moves[moves.length - 1];
if (last && last.user.name !== 'Manager E2E') t.problems.push(`subtask journal by ${last.user.name}, expected Manager E2E`);
if (after.project.name !== move.to) t.problems.push(`subtask is in ${after.project.name}, expected ${move.to}`);
await t.go(`/issues/${child}?tab=history`);
await t.shot('child-history', `PCF Browser child moved along to ${move.to}; its history now says "Project changed from ${move.from} to ${move.to}", by Manager E2E.`);

const mail = newMail(mailsBefore);
if (!/PCF Browser parent/.test(mail)) t.problems.push('no notification for the parent\'s move (expected one from Redmine)');
if (/PCF Browser child/.test(mail)) t.problems.push('a notification went out for the subtask journal');
await t.go(`/issues/${parent}?tab=history`);
await t.shot('parent-history', `The parent's own move, journaled by Redmine as always. Mail: one notification about the parent, ${/PCF Browser child/.test(mail) ? 'AND one about the child' : 'none about the child'}.`);

// Switched off: the subtask moves without a journal, as in core Redmine.
await setJournaling(false, 'journaling off');
await t.shot('setting-off', 'Admin unticks "Record subtasks moved along with their parent in their history".', { full: false });
await t.login('manager');
const silentParent = await pcf.issueId(t, 'PCF Silent parent');
const silentChild = await pcf.issueId(t, 'PCF Silent child');
const silentBefore = projectMoves(await issue(silentChild)).length;
const silentMove = await moveInBrowser(silentParent, 'silent-edit', 'With the journaling off, manager moves PCF Silent parent to %TARGET%.');
const silentAfter = await issue(silentChild);
if (projectMoves(silentAfter).length !== silentBefore) t.problems.push('a subtask journal was written with the setting off');
if (silentAfter.project.name !== silentMove.to) t.problems.push(`silent subtask is in ${silentAfter.project.name}, expected ${silentMove.to}`);
await t.go(`/issues/${silentChild}?tab=history`);
await t.shot('silent-child-history', `Setting off: PCF Silent child moved along to ${silentMove.to}, and its history has no new entry (${projectMoves(silentAfter).length} project moves, as before).`);

await setJournaling(true, 'journaling on');
if (!(await t.page.isChecked('#settings_journal_subtask_moves'))) t.problems.push('journaling not back on');
await t.shot('setting-on', 'The journaling is switched back on (the default).', { full: false });

// Failure path: a reporter may add notes but not edit or move issues, so the
// form offers no project to move to.
await t.login('reporter');
await t.go(`/issues/${child}/edit`);
if (await t.page.locator('#issue_project_id').count()) t.problems.push('reporter is offered the project field');
await t.shot('reporter-no-move', 'Reporter (Reporter role, no "Edit issues") gets the notes-only form: no Project field, so no move.');

await t.done();
