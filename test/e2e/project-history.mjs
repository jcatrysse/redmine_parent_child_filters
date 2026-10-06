// "Project (History)" and "Project (Original)": issues by the projects they
// have been in. PCF Moved parent and its subtask were created in e2e-project
// and moved to e2e-history; the subtask's move is known only through the
// journal the plugin writes for it.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const H = 'e2e-history';
const MOVED = ['PCF Moved parent', 'PCF Moved child'];
// subtask-move-journal.mjs and webhooks.mjs move these between the two projects,
// so on a database where they ran they may show up here too, rightly.
const MOVED_BY_OTHERS = ['PCF Browser parent', 'PCF Browser child', 'PCF Silent parent', 'PCF Silent child'];
const NEVER_MOVED = ['PCF Epic', 'PCF Story', 'PCF Standalone', 'PCF Mention'];
const t = await e2e('project-history');

await t.login('admin');
const ids = {};
for (const p of ['e2e-project', 'e2e-history', 'e2e-private']) {
  ids[p] = String((await pcf.api(t, `/projects/${p}.json`)).body.project.id);
}

await t.login('manager');
await pcf.filtered(t, 'original-inside-project', 'Inside e2e-history, where Redmine has no project filter: Project (Original) is E2E project finds the moved parent AND its subtask.',
  H, [['first_project_id', '=', [ids['e2e-project']]]], { include: MOVED, exclude: NEVER_MOVED });

await pcf.filtered(t, 'history-has-been', 'Project (History) has been E2E project: both moved issues.',
  H, [['project_history_id', 'ev', [ids['e2e-project']]]], { include: MOVED, exclude: NEVER_MOVED });

await pcf.filtered(t, 'history-never-been', 'Project (History) has never been E2E project: the moved issues are left out.',
  H, [['project_history_id', '!ev', [ids['e2e-project']]]], { exclude: MOVED });

await pcf.filtered(t, 'history-changed-from', 'Project (History) changed from E2E project: both moved issues.',
  H, [['project_history_id', 'cf', [ids['e2e-project']]]], { include: MOVED, exclude: NEVER_MOVED });

await pcf.filtered(t, 'history-is', 'Project (History) is E2E history: "is" means the current project.',
  H, [['project_history_id', '=', [ids['e2e-history']]]], { include: MOVED });

await pcf.filtered(t, 'original-global', 'All projects: Project (Original) is E2E history lists none of the moved issues (they started elsewhere).',
  null, [['first_project_id', '=', [ids['e2e-history']]]], { exclude: MOVED });

await pcf.filtered(t, 'original-not', 'All projects: Project (Original) is not E2E project leaves the moved issues and the e2e-project issues out.',
  null, [['first_project_id', '!', [ids['e2e-project']]]], { exclude: [...MOVED, 'PCF Epic'] });

// The subtask's history shows the move the plugin journaled.
const child = await pcf.issueId(t, 'PCF Moved child');
await t.go(`/issues/${child}?tab=history`);
const journal = await t.page.locator('#history .journal', { hasText: 'Project changed from E2E project to E2E history' }).count();
if (!journal) t.problems.push('PCF Moved child: no "Project changed" entry in its history');
await t.shot('subtask-history', 'The history of PCF Moved child shows "Project changed from E2E project to E2E history", by manager, written by the plugin.');

// Failure paths and permissions.
await pcf.filtered(t, 'original-unknown', 'Failure path: Project (Original) is 999999 (no such project): no PCF issue, no error.',
  H, [['first_project_id', '=', ['999999']]], { exact: [] }, { notAnOption: true });

await t.login('outsider');
await t.go(`/projects/${H}/issues`);
await t.page.selectOption('#add_filter_select', 'first_project_id');
await t.page.waitForSelector('#tr_first_project_id select.value option', { state: 'attached', timeout: 10000 })
  .catch(() => t.problems.push('picking Project (Original) added no row'));
const options = await t.page.locator('#tr_first_project_id select.value option').evaluateAll(os => os.map(o => o.textContent.trim()));
if (!options.some(o => o.includes('E2E project'))) t.problems.push(`outsider's values lack the public projects: ${options.join(', ')}`);
if (options.some(o => o.includes('E2E private'))) t.problems.push('outsider is offered E2E private as an original project');
// A <select> does not open in a screenshot, so show its options next to it.
await t.page.evaluate(list => {
  const box = document.createElement('div');
  box.style.cssText = 'border:2px solid #628db6;padding:6px;margin:6px 0;background:#fff';
  box.textContent = 'Values offered for Project (Original): ' + list.join(' | ');
  document.querySelector('#content').prepend(box);
}, options.map(o => o.trim()));
await t.shot('outsider-values', `As outsider: the Project (Original) values do not include the private project (${options.map(o => o.trim()).join(', ')}).`, { full: false });

await pcf.filtered(t, 'outsider-private-original', 'As outsider: Project (Original) is the private project, typed into the URL: nothing from it is revealed.',
  null, [['first_project_id', '=', [ids['e2e-private']]]], { exact: [] }, { notAnOption: true });

await t.done();
