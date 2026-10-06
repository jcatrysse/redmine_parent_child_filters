// Redmine 7 webhooks with the plugin: moving a parent sends one issue.updated
// per issue, the subtask included, with the subtask's new project; the journal
// the plugin writes for the subtask adds no second delivery and nothing to the
// payload. The hook (seeded, owned by manager, on e2e-project and e2e-history)
// posts to the listener this scenario starts on port 3999.
import http from 'node:http';
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const t = await e2e('webhooks');
const received = [];
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', c => { body += c; });
  req.on('end', () => {
    try { received.push(JSON.parse(body)); } catch { received.push({ raw: body }); }
    res.writeHead(200); res.end('ok');
  });
});
await new Promise(r => server.listen(3999, '0.0.0.0', r));

async function waitFor(pred, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (pred()) return true; await new Promise(r => setTimeout(r, 250)); }
  return false;
}

await t.login('manager');
const parent = await pcf.issueId(t, 'PCF Browser parent');
const child = await pcf.issueId(t, 'PCF Browser child');
const before = (await pcf.api(t, `/issues/${parent}.json`)).body.issue.project.name;
const target = before === 'E2E project' ? 'E2E history' : 'E2E project';

await t.go(`/issues/${parent}/edit`);
await t.page.selectOption('#issue_project_id', { label: target });
await t.page.waitForLoadState('networkidle').catch(() => {});
await t.page.waitForTimeout(500);
await t.page.click('#issue-form input[name=commit]');
await t.settle();
t.check('move parent');

const updated = id => received.filter(p => p.type === 'issue.updated' && p.data && p.data.issue && p.data.issue.id === id);
await waitFor(() => updated(parent).length && updated(child).length);
await new Promise(r => setTimeout(r, 2000)); // a late duplicate would arrive here
server.close();

const forParent = updated(parent);
const forChild = updated(child);
if (forParent.length !== 1) t.problems.push(`${forParent.length} issue.updated deliveries for the parent, expected 1`);
if (forChild.length !== 1) t.problems.push(`${forChild.length} issue.updated deliveries for the subtask, expected 1`);
const childIssue = forChild[0] && forChild[0].data.issue;
if (childIssue && childIssue.project.name !== target) t.problems.push(`subtask payload carries project ${childIssue.project.name}, expected ${target}`);
if (childIssue && childIssue.journals) t.problems.push('subtask payload carries journals; core sends none');

const summary = received.map(p => `${p.type} #${p.data && p.data.issue ? p.data.issue.id : '?'} (${p.data && p.data.issue ? p.data.issue.project.name : ''})`);
const pretty = JSON.stringify(childIssue || {}, null, 2).replace(/</g, '&lt;');
await t.page.setContent(`<html><body style="font:13px sans-serif;margin:16px"><h2>Webhook deliveries after moving #${parent} to ${target}</h2>
<p>${summary.map(s => s.replace(/</g, '&lt;')).join('<br>')}</p><h3>Payload for the subtask #${child}</h3><pre style="font-size:11px">${pretty}</pre></body></html>`);
await t.shot('deliveries', `Moving PCF Browser parent to ${target} sent ${received.length} deliveries: ${summary.join(', ')}. One issue.updated for the subtask, with its new project, as core sends it.`);

await t.done();
