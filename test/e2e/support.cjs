// Shared by this plugin's scenarios (test/e2e/*.mjs). A .cjs file so that
// .codex/e2e.sh, which runs every *.mjs here, does not run it as a scenario.

// The issue list of a project with the given filters, and nothing else: no
// default "status is open", every issue on one page, sorted by id.
//   filterPath('e2e-project', [['child_tracker_id', '=', ['1']]])
function filterPath(project, filters, { columns = ['tracker', 'status', 'subject', 'project'] } = {}) {
  const q = new URLSearchParams();
  q.append('set_filter', '1');
  q.append('sort', 'id');
  q.append('per_page', '100');
  for (const c of columns) q.append('c[]', c);
  q.append('f[]', '');
  for (const [field, op, values = []] of filters) {
    q.append('f[]', field);
    q.append(`op[${field}]`, op);
    for (const v of values) q.append(`v[${field}][]`, v);
  }
  const base = project ? `/projects/${project}/issues` : '/issues';
  return `${base}?${q.toString()}`;
}

// Subjects of the PCF issues on the current issue list.
async function subjects(page) {
  const cells = await page.locator('table.issues tr.issue td.subject').allInnerTexts();
  return cells.map(s => s.trim()).filter(s => s.startsWith('PCF ')).sort();
}

// Compares what the list shows with what the scenario expects, as a problem
// on the run when they differ, and returns the subjects for the caption.
async function expectSubjects(t, step, { include = [], exclude = [], exact } = {}) {
  const got = await subjects(t.page);
  if (exact) {
    const want = [...exact].sort();
    if (JSON.stringify(got) !== JSON.stringify(want)) {
      t.problems.push(`${step}: expected exactly [${want.join(', ')}], got [${got.join(', ')}]`);
    }
  }
  for (const s of include) if (!got.includes(s)) t.problems.push(`${step}: "${s}" missing, got [${got.join(', ')}]`);
  for (const s of exclude) if (got.includes(s)) t.problems.push(`${step}: "${s}" shown but must not be`);
  return got;
}

// Opens the filtered list, checks the result and takes the screenshot.
async function filtered(t, shot, caption, project, filters, expectation, opts = {}) {
  await t.go(filterPath(project, filters, opts), opts.go || {});
  const got = await expectSubjects(t, shot, expectation);
  await t.shot(shot, `${caption} Result: ${got.length ? got.join(', ') : 'no PCF issue'}.`);
  return got;
}

// GET on the REST API as one of the seeded users (HTTP Basic, the way an API
// client authenticates), returning the status and the parsed body.
const PASSWORD = process.env.RMP_USER_PASSWORD || process.env.RMP_ADMIN_PASSWORD || 'Redmine7Test!';
async function api(t, path, login = 'admin') {
  const auth = 'Basic ' + Buffer.from(`${login}:${login === 'admin' ? (process.env.RMP_ADMIN_PASSWORD || 'Redmine7Test!') : PASSWORD}`).toString('base64');
  const res = await t.page.request.get(t.BASE + path, { headers: { Authorization: auth }, maxRedirects: 0 });
  let body = null;
  try { body = await res.json(); } catch { /* not JSON */ }
  return { status: res.status(), body };
}

// Id of an issue by subject, as admin sees it through the REST API.
async function issueId(t, subject) {
  const { body } = await api(t, `/issues.json?subject=${encodeURIComponent('~' + subject)}&status_id=*&limit=100`);
  const issue = ((body && body.issues) || []).find(i => i.subject === subject);
  if (!issue) throw new Error(`no issue "${subject}" visible to the current user`);
  return issue.id;
}

module.exports = { filterPath, subjects, expectSubjects, filtered, api, issueId };
