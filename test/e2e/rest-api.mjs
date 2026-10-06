// The filters through the REST API (/issues.json), the way scripts and other
// tools use them: both parameter styles, the permissions, and the refusals.
import { e2e } from '../../.codex/e2e/lib.mjs';
import pcf from './support.cjs';

const t = await e2e('rest-api');
const rows = [];

function subjectsOf(body) {
  return ((body && body.issues) || []).map(i => i.subject).filter(s => s.startsWith('PCF ')).sort();
}

async function call(login, path, { status = 200, include = [], exclude = [], exact } = {}) {
  const res = await pcf.api(t, path, login);
  const got = subjectsOf(res.body);
  const fail = [];
  if (res.status !== status) fail.push(`HTTP ${res.status}, expected ${status}`);
  if (exact && JSON.stringify(got) !== JSON.stringify([...exact].sort())) fail.push(`got [${got.join(', ')}], expected [${[...exact].sort().join(', ')}]`);
  for (const s of include) if (!got.includes(s)) fail.push(`"${s}" missing`);
  for (const s of exclude) if (got.includes(s)) fail.push(`"${s}" must not be returned`);
  for (const f of fail) t.problems.push(`${login} GET ${path}: ${f}`);
  const errors = res.body && res.body.errors ? ` errors: ${res.body.errors.join('; ')}` : '';
  rows.push({ login, path, status: res.status, result: (got.join(', ') || '(no PCF issue)') + errors, ok: fail.length === 0 });
}

await t.login('admin');
const epic = await pcf.issueId(t, 'PCF Epic');
const q = '/issues.json?project_id=e2e-project&status_id=*&limit=100';

await call('manager', `${q}&f[]=child_tracker_id&op[child_tracker_id]==&v[child_tracker_id][]=1`,
  { include: ['PCF Story', 'PCF Parent of hidden'], exclude: ['PCF Epic'] });
await call('manager', `${q}&child_tracker_id=1`, { include: ['PCF Story', 'PCF Parent of hidden'], exclude: ['PCF Epic'] });
await call('manager', `${q}&root_id=${epic}`, { exact: ['PCF Epic', 'PCF Story', 'PCF Task open', 'PCF Task closed'] });
await call('manager', `${q}&a_specific_parent_tracker_id=2:2`, { exact: ['PCF Task open', 'PCF Task closed'] });
await call('manager', `${q}&tree_has_parent_or_child=0`, { include: ['PCF Standalone'], exclude: ['PCF Epic'] });
await call('manager', `${q}&involved_id=me`, { include: ['PCF Watched'] });
await call('manager', '/issues.json?project_id=e2e-history&status_id=*&limit=100&first_project_id=1', { include: ['PCF Moved parent', 'PCF Moved child'] });
await call('manager', `${q}&f[]=start_date&op[start_date]=!&v[start_date][]=2026-01-15`, { include: ['PCF Standalone'], exclude: ['PCF Dated'] });

// Without access to the private project, its subtask is not there.
await call('reporter', `${q}&child_tracker_id=1`, { include: ['PCF Story'], exclude: ['PCF Parent of hidden'] });
await call('reporter', `${q}&child_status_id=!*`, { include: ['PCF Parent of hidden'] });
await call('reporter', '/issues.json?status_id=*&limit=100&f[]=a_child_tracker_id&op[a_child_tracker_id]=*',
  { include: ['PCF Epic', 'PCF Story'], exclude: ['PCF Hidden child', 'PCF Parent of hidden'] });

// Refusals.
await call('outsider', '/issues.json?project_id=e2e-private&status_id=*&child_tracker_id=*', { status: 403 });
await call('manager', `${q}&f[]=start_date&op[start_date]=!&v[start_date][]=abc`, { status: 422 });
await call('manager', `${q}&a_specific_parent_tracker_id=2:99`, { exact: [] });
await call('manager', `${q}&root_id=1%20OR%201=1`, { exact: [] });

// Render the calls as a page, so the evidence is a screenshot like the others.
const html = `<html><body style="font:13px sans-serif;margin:16px"><h2>REST API: /issues.json with the plugin's filters</h2>
<table border="1" cellpadding="4" style="border-collapse:collapse">
<tr><th>user</th><th>request</th><th>HTTP</th><th>PCF issues returned</th><th>as expected</th></tr>
${rows.map(r => `<tr><td>${r.login}</td><td><code>${r.path.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</code></td><td>${r.status}</td><td>${r.result.replace(/</g, '&lt;')}</td><td>${r.ok ? 'yes' : '<b style="color:red">NO</b>'}</td></tr>`).join('\n')}
</table></body></html>`;
await t.page.setContent(html);
await t.shot('calls', `${rows.length} API calls as manager, reporter and outsider: results, permissions (private subtask hidden, private project 403) and refusals (invalid date 422, depth 99 and "1 OR 1=1" match nothing).`);

await t.done();
