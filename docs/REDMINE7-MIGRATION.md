# Redmine 7 migration: redmine_parent_child_filters

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. That includes the plugin's tests on
> PostgreSQL and MariaDB, every function exercised end to end on a real running Redmine in a
> browser (with and without permissions, failure paths included) with screenshots you looked at,
> and an OpenAI review of the diff when OPENAI_API_KEY is set. Report to me in Dutch at the end.

This file is the plan and the memory of that work. Update it as you go: verdicts, results,
what is left. Written 2026-10-06 from a measured analysis (report at the bottom).

## Status

| | |
|---|---|
| Plugin id | `redmine_parent_child_filters` |
| GEOxyz runs today | `main` |
| Upstream | geen |
| Runs on Redmine 7 as is | JA (two pre-existing defects found and fixed on this branch, see below) |
| Upstream sync | GEEN UPSTREAM |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 1 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz 8067e23), Rails 8.1, Ruby 3.3.6, PostgreSQL 16.15, alone and with all 43 GEOxyz plugins (2026-10-07). Earlier, no longer required: MariaDB 10.11.14, Redmine 5.1.13 |
| Migration session | done 2026-10-06; Jan's decisions of 2026-10-07 built the same day; see "Decided by Jan" and "Results" |

## Already on this branch

Commits since the plan (`6596c05`), one concern each:

- **Fix: "is not" on a date filter refuses a value that is not a date** (`ddbbf2a`). Redmine validates
  `=`, `>=`, `<=`, `><` on dates but not the `!` this plugin adds; `start_date is not abc` answered 500
  on PostgreSQL and matched every issue on MariaDB. Pre-existing (5.1 too, see `docs/e2e/before/`).
  `spec/date_operator_spec.rb`, 3 examples fail without it.
- **Fix: the people filters no longer reveal a field another plugin hides** (`a18f3c6`). With
  redmine_issue_field_visibility hiding the assignee or the description from a role, "Assignee, author
  or watcher" still matched the assignee and the mention filters still searched the description.
  Found in the combination run (step 7). The assignee leg and the description search are now used only
  while the query offers Redmine's own filter on them; without such a plugin nothing changes.
  `spec/hidden_fields_spec.rb` (4 of 7 fail without it), contract in `spec/core_contract_spec.rb`.
  Pre-existing (5.1 too, see `docs/e2e/before/`). Kept by Jan's decision 1 (2026-10-07).
- **E2E**: `test/e2e/seed.rb`, `test/e2e/support.cjs` and 15 scenarios, one per function (inventory below).
- **Tooling**: `.codex/start_server.sh` granted the e2e database to an account MariaDB does not have
  (`1179bbe`); `.codex/redmine_clone.sh` header documents `REDMINE_REPO` + `7.0-stable-GEOxyz`.
- **Decision 3 (Jan, 2026-10-07): "none" in the dropdown of the status filters of a relative that may be
  missing** (`a40b42c`). Parent task, Parent task (any), Subtasks, Subtasks (any), Tree / Parent task and
  Tree / Subtasks: Status get the filter type `:pcf_list_status` (Redmine's `:list_status` plus `!*`,
  before `*`); Root: Status, Tree: Status and Redmine's own Status keep `:list_status`.
  `assets/javascripts/pcf_filters.js`, loaded through `view_layouts_base_html_head`, makes Redmine's
  filter form draw the new type. `spec/status_none_operator_spec.rb`: 10 of its 14 examples fail
  without the change (the commit message says 12; 10 is the count). The settings spec's "ships no
  JavaScript" now allows exactly this one script, which belongs to the filter form.
  E2E `status-none.mjs`, 10 screenshots.
- **Specs that hold with all GEOxyz plugins** (`52fbdb9`): the status-history setup uses a fresh Issue
  per change, the ivar contract tolerates a plugin adding a filter on read (redmineup_tags). No
  assertion changed.
- **E2E `core-pages.mjs`** (Jan's general decision): Project > Settings, issue list, issue page.
- CHANGELOG "Unreleased" and README ("A field hidden from you stays hidden", "none" on the status
  filters) updated; COMPATIBILITY.md describes the `buildFilterRow` wrap. Version left at 1.1.0.

## Inventory of functions

No routes, controllers, permissions, menus, project modules, hooks, macros, mail handlers, rake tasks or
migrations: the plugin adds query filters, one operator, one journal on subtask moves, and a settings
page. Every function, how a user reaches it, and the evidence (screenshots in `docs/e2e/`, the table per
scenario in `docs/e2e/<scenario>.md`):

| Function | How a user reaches it | Scenario | Screenshots (who / path) |
|---|---|---|---|
| Plugin settings page (26 switches, depth bounds, effective range) | Administration > Plugins > Configure | `settings.mjs` | admin page, Root off, reversed depth 3/2 shown as 3–3, restore; manager 403, reporter 403, anonymous to login, POST by manager refused |
| Switch a filter off | settings | `settings.mjs` | Root gone from the dropdown, a URL still carrying it is ignored |
| Depth bounds of "Parent task (level)" | settings | `settings.mjs`, `filter-group.mjs` | values (1)..(5), then only (3) |
| Filter group "Parent and child" in Add filter | issue list | `filter-group.mjs` | manager, reporter, outsider, anonymous; picking adds rows; private project 403 for outsider |
| Root, Root: Tracker, Root: Status | issue list / API | `root-filters.mjs` | is, is not, closed, invalid id, id list; reporter |
| Parent task: Tracker/Status, has been | issue list | `parent-filters.mjs` | is, is not, `ev` |
| Parent task (any): Tracker/Status, paired | issue list | `parent-filters.mjs` | any level, pair on one ancestor |
| Parent task (level): Tracker/Status | issue list | `parent-filters.mjs` | (2) Feature, mixed depths, depth 99 and garbage refused quietly |
| Subtasks: Tracker/Status, paired, any/none | issue list | `child-filters.mjs` | manager sees the subtask in the private project, reporter does not (is, any, none, all projects) |
| Subtasks (any): Tracker/Status | issue list | `child-filters.mjs` | two levels down |
| Tree filters (has parent or subtask, tree, tree/parent, tree/subtasks) | issue list | `tree-filters.mjs` | yes/no, closed, tracker, reporter with a hidden relative, invalid flag |
| Assignee, author or watcher | issue list | `people-filters.mjs` | manager, reporter (me, not me), watchers hidden without "View watchers list" |
| Mentioned or linked; Assignee, author, watcher, mentioned or linked | issue list | `people-filters.mjs` | @login, user#id, private note for manager only, garbage value |
| Hidden core fields (with redmine_issue_field_visibility) | issue list | `hidden-fields.mjs` | before/after hiding assignee and description from Reporter; manager unchanged; restored. Before pictures in `docs/e2e/before/` |
| Project (History), Project (Original) | issue list, inside a project too | `project-history.mjs` | original, has been, never been, changed from, is; global; subtask history; unknown project; outsider's values and private project |
| "is not" on date filters | issue list | `date-not-operator.mjs` | operator offered, is, is not, due date, invalid date refused (was 500, `docs/e2e/before/`) |
| Journal for subtasks moved with their parent | issue edit form (move) | `subtask-move-journal.mjs` | child history by manager, parent history, one mail for the parent and none for the child, setting off = no journal, reporter has no project field |
| REST API `/issues.json` with the filters | API (Basic auth) | `rest-api.mjs` | 15 calls: both parameter styles, reporter visibility, outsider 403, invalid date 422, depth 99 and `1 OR 1=1` match nothing |
| Redmine 7 webhooks | webhook to a local listener | `webhooks.mjs` | one `issue.updated` per moved issue, subtask payload with its new project, no duplicate |
| "none" on six status filters (decision 3) | issue list, Add filter, saved query | `status-none.mjs` | offered to admin, manager, reporter, outsider on the six, not on Status, Root: Status, Tree: Status; applied through the form as manager and reporter (private subtask respected); Parent task none, Tree / Subtasks none; saved query reopens with none; private project 403 |
| Core pages with the plugin (and with all GEOxyz plugins) | Project > Settings, issue list, issue page | `core-pages.mjs` | admin and manager 200; reporter Settings 403; outsider private Settings 403; combination results in `docs/e2e/geoxyz-all/` |
| Core pages and flows with the plugin | | `.codex/e2e/smoke.mjs`, `core.mjs` | 11 + 6 screenshots |

## Work list for the migration session

1. Geen migratiewerk; `claude/codex-script-fixes` (only .codex tooling) can be merged separately.
   **Done**: nothing needed on this branch for it. Not merged here (another branch).
2. Integration: order of `alias_method` (issue_field_visibility, itil_priority) vs `prepend` (this plugin)
   on `IssueQuery#initialize_available_filters`. **Done, confirmed**:
   - Installed together (`redmine70-migration` heads of both): load order `[:redmine_issue_field_visibility,
     :redmine_itil_priority, :redmine_parent_child_filters]`, 68 filters, rspec and the whole e2e set
     green on MariaDB (numbers below).
   - The reverse (an `alias_method` chain set *after* this plugin's prepends) was reproduced in a
     runner: `SystemStackError: stack level too deep` on `available_filters`. It does not happen with
     the GEOxyz set: of all 47 jcatrysse plugin repositories, only redmine_issue_field_visibility,
     redmine_itil_priority and redmine_issue_todo_lists2 alias-chain that method, and all three sort
     before `redmine_parent_child_filters` (Redmine loads plugins in directory order). Recorded under
     "After the upgrade".
   - The combination found a real leak, fixed: see "Already on this branch".
3. Tests on 7.0-stable-GEOxyz with PostgreSQL and MariaDB, and on 5.1-stable. **Done**, see "Results".
4. Webhooks. **Done, nothing needed**: core sends `issue.updated` from `after_update_commit` for every
   saved issue, so a subtask moved with its parent was already delivered by core before this plugin; the
   journal the plugin adds is written in the same save and adds no delivery and nothing to the payload
   (`issues/show.api.rsb` without journals). The filters change no issue data. Shown end to end in
   `webhooks.mjs` (2 deliveries for a parent and its subtask). The hidden-fields fix concerns filters
   only; payload visibility of assignee/description under redmine_issue_field_visibility is that
   plugin's concern.
5. Every feature by hand on Redmine 7 with screenshots. **Done**: inventory above.

## Results

**2026-10-07, after Jan's decisions (PostgreSQL 16 only, as decided):**

| Run | Plugins | rspec | e2e scripts / screenshots / problems |
|---|---|---|---|
| 7.0-stable-GEOxyz | alone | 756 examples, 0 failures, 2 pending (MySQL only) | 17 / 131 / 0 (`docs/e2e/`) |
| 7.0-stable-GEOxyz | all 43 GEOxyz plugins, `redmine70-migration` heads, with the ifv test shim below | 756 examples, 0 failures, 2 pending | 17 / 136 / 5, none from this plugin (`docs/e2e/geoxyz-all/`) |

RuboCop 1.88.2: no offenses. Every screenshot of the new and changed scenarios (status-none,
core-pages, both runs) was opened; the others were checked against their captions on 2026-10-06.

Combination findings, none in this plugin (it uses `prepend` only):
- **redmine_issue_field_visibility + redmine_agile**: ifv alias-chains
  `IssueQuery#initialize_available_filters` (and `available_columns`, `Issue#reload`), agile prepends
  it; together `SystemStackError`, so the full set does not even load its default data. Jan's rule
  (prepend, never alias_method) applies to ifv. For these runs ifv was switched to `prepend` in the
  test checkout only (not pushed anywhere); with that, everything above is green.
- **Project > Settings answers 500** with the full set: `super: no superclass method
  project_settings_tabs`, through redmine_mail_digest (`project_settings_tabs_with_issue_digest`, an
  alias chain) and redmine_wiki_extensions. The case Jan named; for those plugins.
- **redmine_view_issue_description** refuses issue pages and the edit form to the core Reporter role
  (403, `vid_authorize_issue_detail`): by design of that plugin, the role lacks its permission.
- **redmine_contacts_helpdesk**: with its Journal patch, a second change saved through the same Issue
  object on the same journal is not recorded (core records it). Not reachable from a single request;
  a script or plugin that saves an issue twice would lose the second change. For that plugin.

**2026-10-06 (history):**

**rspec** (`./.codex/test_plugin.sh`):

| Redmine | Database | Plugins | Before (main) | This branch |
|---|---|---|---|---|
| 7.0-stable-GEOxyz | PostgreSQL 16 | alone | 728, 0 failures, 2 pending (MySQL only) | 742, 0 failures, 2 pending (MySQL only) |
| 7.0-stable-GEOxyz | MariaDB 10.11 | alone | 728, 0 failures, 1 pending (PostgreSQL only) | 742, 0 failures, 1 pending (PostgreSQL only) |
| 7.0-stable-GEOxyz | MariaDB 10.11 | + issue_field_visibility + itil_priority | | 742, 0 failures, 1 pending |
| 7.0-stable-GEOxyz | PostgreSQL 16 | + issue_field_visibility + itil_priority | | 742, 0 failures, 2 pending |
| 5.1-stable | PostgreSQL 16 | + issue_field_visibility (master) | | 742, 0 failures, 2 pending |

RuboCop 1.88.2 (the lint workflow's version): no offenses. `.codex/test_scripts.sh`: 12 checks, 0 failures.

**e2e** (`./.codex/start_server.sh --reset` then `./.codex/e2e.sh`, production mode):

| Redmine | Database | Plugins | Scripts | Screenshots | Problems |
|---|---|---|---|---|---|
| 7.0 baseline (main, before any change) | PostgreSQL | alone | smoke + core | 17 | 0 |
| 7.0 | PostgreSQL | + ifv + itil (`docs/e2e/`) | 15 | 116 | 0 |
| 7.0 | MariaDB | + ifv + itil (`docs/e2e/mariadb/`, tables only) | 15 | 116 | 0 |
| 5.1 | PostgreSQL | + ifv (master) (`docs/e2e/redmine51/`, tables only) | 15 | 116 | 0 |
| 5.1, branch main (`docs/e2e/before/`) | PostgreSQL | + ifv (master) | 2 | 11 | 3, the two defects fixed here |

Screenshots in `docs/e2e/`: all 116 were opened and checked against their caption and user (by a
review subagent, then the rejected ones by me). That check found five scenarios whose picture did not
prove the caption (two option lists read as empty, so their assertions could not fail; two settings
shots cut off the checkbox in question; one caption wrong about the documented standalone matches of
the tree filters) and eight shots where a value from the URL is not one of the options, so the value
box shows its first option. All fixed in the scenarios and run again from a fresh database on both
engines; captions now say when the value box shows a fallback. The 5.1 tables in `docs/e2e/redmine51/`
are from the scenarios before that fix. Plain
PostgreSQL and MariaDB runs without the other plugins were green as well during the session (14
scripts each, before `hidden-fields.mjs` existed). Migrations: the plugin has none; boot and eager
load in production mode are exercised by every server start.

**Review**: own adversarial review of the whole diff (added the contract rows for the core methods the
fixes use); OpenAI review `docs/reviews/openai-2026-10-06-5c045a2.md` (gpt-5, range 5a82e2f..5c045a2):
no findings. Second run after the e2e fixes, `docs/reviews/openai-2026-10-06-3a69730.md`: one finding
(SQL injection through the principal ids), rejected with the reason there: the ids are parsed strictly
before they reach the SQL, covered by `spec/security_spec.rb`.

**Found elsewhere, not fixed here** (rule: write down, do not fix in passing):
- Redmine core (7.0-stable-GEOxyz): `GET /issues.json?tracker_id=*` answers 500
  (`PG::InvalidTextRepresentation`): the legacy short filter turns `*` into a value for a `:list` filter
  that has no `*` operator. Same pattern for this plugin's list filters returns an empty list, not an
  error.
- redmine_issue_field_visibility hides fields per role; webhooks and the REST API of core are its
  concern, not this plugin's.
- redmine_itil_priority (`redmine70-migration` head) on Redmine 7: the priority field on the issue form
  shows a garbled glyph next to "Normal" (an icon that does not resolve), and its Urgency and Impact
  selects are empty in e2e-project (`docs/e2e/core-new-issue-form.png`,
  `subtask-move-journal-edit-form.png`). For that plugin's migration.
- README "Filter semantics" says `Subtasks: Status` **none** is "has no subtask". It works through the
  URL, the API and saved queries, but Redmine's status filter type (`:list_status`) offers no "none"
  in the dropdown, and the tracker filters (`:list`) neither "any" nor "none". Documentation only;
  see open question 4.

## Decided by Jan

Answered by Jan on 2026-10-07 in the coordinating session (recorded verbatim in
`docs/DECISIONS-2026-10-07.md`). Final.

**General, for every GEOxyz plugin (2026-10-07)**
- Straight to Redmine 7, no backports to 5.1; `redmine70-migration` is what goes live. Redmine 5.1
  compatibility is no longer a requirement (rules below updated).
- PostgreSQL 16 only: tests and e2e on PostgreSQL; MariaDB runs no longer required, a MariaDB-only
  problem is a note, not a blocker. The MariaDB results above stay as history.
- deface without a version constraint: n/a, this plugin does not use deface.
- A core method other plugins also patch is patched with `prepend`, never `alias_method`: this plugin
  already uses `prepend` everywhere (no `alias_method` in `lib/` or `init.rb`); checked with the other
  GEOxyz plugins installed, see "Results".
- GitHub Actions stay manual only: unchanged, all workflows are `workflow_dispatch`.

**This plugin**
1. *Hoe gaan de personenfilters om met velden die voor een rol verborgen zijn?* (2026-10-07)
   Jan chose A: "Algemene aanpak, zoals gebouwd" (Werkt met elke plugin die velden verbergt, zonder
   vaste koppeling; wie de velden niet mag zien, vindt er ook via deze filters niets meer mee.).
   Already built in `a18f3c6`; kept.
2. *Laten we de beperking in laadvolgorde van plugins zo, of passen we de techniek van de plugin aan?*
   (2026-10-07) Jan chose A: "Zo laten en nieuwe plugins hierop controleren" (Geen wijziging nu; bij
   elke nieuwe plugin moet iemand dit nakijken.). No code change; the check is listed under
   "After the upgrade".
3. *Hoe maken we 'geen' bij de statusfilter voor subtaken bruikbaar?* (2026-10-07) Jan chose B:
   "De keuze 'none' aan de keuzelijst toevoegen" (Gebruikers kunnen het zelf kiezen, maar het is een
   nieuwe optie op het scherm en dus een gedragswijziging.). Built, see "Already on this branch".

## Open questions for Jan

1. **Version number** (not part of the 2026-10-07 answers): the fixes sit under "Unreleased" in the
   CHANGELOG, `init.rb` still says 1.1.0. Recommendation: release as 1.1.1 (or 1.2.0, since decision 3
   adds an operator) when this branch goes live.

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- None required: no migration, no setting, no data fix. Replace the folder and restart.
- Keep the plugin directory named `redmine_parent_child_filters`. Decision 2 (Jan, 2026-10-07): for
  every new plugin, check that it does not alias-chain `IssueQuery#initialize_available_filters`
  (Jan's rule: prepend only). redmine_issue_field_visibility does so today and must be on `prepend`
  before it goes live next to redmine_agile (see "Results").
- Decision 3: users see "none" in the operator list of six status filters (new option, documented in
  the README). The browser loads one small script, `plugin_assets/redmine_parent_child_filters/pcf_filters.js`;
  nothing to configure.
- If redmine_issue_field_visibility hides the assignee or the description from a role, users with that
  role will no longer find issues through those fields in the people filters (intended, see question 1).
- Subtasks moved before the plugin journaled such moves still have no history entry; nothing to do.

## How to test

This repo already has its own `.codex/` scripts (older variant). Read their headers and use them; check they accept `7.0-stable-GEOxyz` (clone from https://github.com/jcatrysse/redmine.git) and MariaDB. The shared variant from the other plugin repos may replace them if that is simpler.

Checked in the migration session: they do.

```sh
REDMINE_REPO=https://github.com/jcatrysse/redmine.git ./.codex/redmine_clone.sh 7.0-stable-GEOxyz
PCF_DB=postgresql ./.codex/test_setup.sh && ./.codex/test_plugin.sh     # or PCF_DB=mariadb
```

- Switching the database means running `test_setup.sh` again (it rewrites `database.yml` and the
  bundle groups); then `start_server.sh --reset`.
- After a change to the plugin, copy it into the checkout again (`redmine_clone.sh`, or
  `rsync -a --delete --exclude /redmine/ --exclude /.git/ ./ redmine/plugins/redmine_parent_child_filters/`)
  and restart the server (`start_server.sh`).
- Do not pipe `start_server.sh` into another command: the server keeps the pipe open. Redirect to a file.
- Redmine 5.1 needs Ruby < 3.3: `PATH=/opt/rbenv/versions/3.2.6/bin:$PATH`, its own `REDMINE_DIR`,
  `PCF_DB_NAME`, `RMP_PORT` and `RMP_SERVER_DB_NAME`.
- Combination: copy redmine_issue_field_visibility and redmine_itil_priority into `redmine/plugins/`,
  `bundle install`, `rake redmine:plugins:migrate` for test and production; `hidden-fields.mjs` needs the
  first one and records a skip without it.

Then the real Redmine and the browser checks (shared scripts, they use the checkout in `redmine/` or `REDMINE_DIR`):

```sh
./.codex/start_server.sh       # real Redmine (production mode) with this plugin, seeded users and projects
./.codex/e2e.sh                # browser: smoke over the plugin's pages, core issue flows, test/e2e/*.mjs
./.codex/openai_review.sh      # independent OpenAI review of the diff, only when OPENAI_API_KEY is set
```
Write one scenario per function in `test/e2e/<function>.mjs` (example at the top of
`.codex/e2e/lib.mjs`); screenshots and a table per scenario land in `docs/e2e/`. Users:
`admin`, `manager` (every permission), `reporter` (no plugin permissions), `outsider` (no
membership); password `Redmine7Test!`. Needs Node with Playwright and Chromium
(`npm install -g playwright && npx playwright install --with-deps chromium`).

The coordinator's harness (`plugin-check.sh` in the migration kit, kept outside this repo) adds a
browser smoke test of every page the plugin adds and runs all GEOxyz plugins together; the
results quoted in the analysis come from it.

## How the migration session works (same for every plugin)

1. **Start**: `git fetch && git checkout redmine70-migration && git pull`. Read this whole file,
   including the analysis report at the bottom. Do not reopen decisions recorded here.
2. **Baseline, before you change anything**:
   - the plugin's tests on Redmine 7.0-stable-GEOxyz with PostgreSQL and with MariaDB;
   - a real running Redmine with this plugin (`./.codex/start_server.sh`) and the browser run
     (`./.codex/e2e.sh`: smoke over every page the plugin adds, plus the core issue flows).
   Write the numbers here. Something already broken now is a finding, not your regression.
3. **Inventory of functions**: list every function of the plugin in this file, in a table
   "function | how a user reaches it | scenario | screenshot". Take them from the README,
   `init.rb` (permissions, menus, settings, project modules), routes, hooks and view
   overrides, macros, mail handling, API endpoints, rake tasks and cron jobs. This table is the
   coverage list for step 8; a function that is not in it will not be tested.
4. **GEOxyz changes**: go through the table above, one item at a time. Each kept or re-made change
   is its own commit with a test that proves it. Record the verdict in the table.
5. **Work list**: then the numbered list, in order. One concern per commit.
6. **Portability**: GEOxyz runs PostgreSQL 16 only (Jan, 2026-10-07): tests, migrations (down and
   up) and the e2e set run on PostgreSQL. Keep SQL portable where that costs nothing; a
   MariaDB-only problem is a note in this file, not a blocker.
7. **Together**: run with the other GEOxyz plugins installed (the migration kit's harness, or
   `RMP_EXTRA_PLUGINS`). A failure that only appears in combination is a finding to record here.
8. **End to end, visually, every function**: on the real Redmine from `start_server.sh`
   (production mode, the way GEOxyz runs it), write one scenario per function in
   `test/e2e/<function>.mjs` with `.codex/e2e/lib.mjs` and run them with `./.codex/e2e.sh`.
   - Each function as the users that matter: `admin`, `manager` (every permission, the
     plugin's included), `reporter` (member without the plugin's permissions), `outsider`
     (no membership, private project must stay invisible).
   - The failure paths too: setting off, permission absent, empty state, invalid input, the
     value that used to raise. A refusal that is shown is evidence as much as a success.
   - One screenshot per function and per path, with a caption saying what it proves. Open
     every screenshot and look at it: a picture nobody looked at proves nothing. Commit them
     in `docs/e2e/` and list them in the inventory table.
   - Functions without a page (mail in and out, REST API, rake tasks, cron, webhooks): exercise
     them against the same running instance (mails land in `redmine/tmp/mails`, `t.mails()`
     reads them; API through `t.page.request`) and record command and result.
   - Before pictures where behaviour or layout changes: the branch GEOxyz runs today, on
     Redmine 5.1, same scenarios, `RMP_E2E_OUT=docs/e2e/before`.
   - MariaDB runs are no longer required (Jan, 2026-10-07).
9. **Independent review**: first your own, adversarial: re-read the whole diff as if someone
   else wrote it and you are paid to reject it. Then, **when `OPENAI_API_KEY` is set in the
   session**, `./.codex/openai_review.sh`: it sends the diff of this branch to an OpenAI model
   and writes `docs/reviews/openai-<date>-<sha>.md`. Every finding gets a `Resolution:` line
   there (fixed in <commit>, with a test, or why not). Fix, re-run the tests and the e2e set,
   and run the review again until it has nothing new that you accept. Without the key: write
   "OpenAI review: skipped, no OPENAI_API_KEY" in the report; never send code anywhere else.
10. **After the upgrade**: anything the production upgrade must do for this plugin (data fixes,
    settings, cron, files, removed features) goes into the section "After the upgrade".
11. **Finish**: update "Status", the inventory and the work list in this file, push
    `redmine70-migration`, and report: what changed, test numbers on both databases, e2e
    numbers (scenarios, screenshots, problems), the review result, what is left, what needs Jan.

### Stop and ask Jan when
- a GEOxyz change would be lost or behave differently for users;
- a new gem, a new setting with user impact, or a schema change not required by Redmine 7 seems needed;
- the change would send data to an external service (the OpenAI review of the code diff is the
  one exception Jan approved, and only when the key is present);
- upstream and GEOxyz disagree on behaviour and both are defensible.

## Rules

- **Target**: Redmine 7.0-stable-GEOxyz (https://github.com/jcatrysse/redmine), Rails 8.1, Ruby 3.3+.
  Core sources for comparison: branches `5.1-stable`, `6.1-stable`, `7.0-stable`, `7.0-stable-GEOxyz`.
- **Evidence**: never report a test, lint, browser check or review as passed without having seen
  it. Quote the summary lines; list the screenshots. "Should work" is not a result, and a green
  test suite is not proof that a feature works in the browser.
- **Tests**: never skip, delete or weaken a test. A test that encodes Redmine 5 markup or
  behaviour is updated to Redmine 7, with the reason in the commit. Every fix gets a test that
  fails without it.
- **Minimal diffs** in the plugin's own style. No reformatting, no unrelated refactoring.
  Something wrong elsewhere: write it down here, do not fix it in passing.
- **Security**: authorization on every action and entry point; `safe_attributes`, never
  `to_unsafe_hash` into `update`; no SQL built from params; no secrets in logs; no `html_safe` on
  user input.
- **Webhooks (new in Redmine 7)**: core sends issue payloads (core `issues/show.api.rsb`, rendered
  as the webhook owner) to webhook endpoints, past plugin hooks and controller patches. If the
  plugin hides, adds or changes issue data, make webhooks consistent with that or record why not.
- **Redmine 7 conventions**: SVG icons through `sprite_icon` (the `icon icon-*` CSS is gone),
  Propshaft assets under `assets/` (`/assets/plugin_assets/<id>/...`), the new header and user menu,
  `ContextMenus::*Controller`, Loofah-based text formatting, Chart.js as an ES module, sudo mode
  (on by default: `t.sudo()` in a scenario). The breaker list is in the migration kit's CHECKLIST.md.
- **Locales**: keep the locales the plugin ships in sync; translate a new key by matching the
  closest existing key in the same file, not from scratch; do not add new languages.
- **No 5.1** (Jan, 2026-10-07): GEOxyz goes straight to Redmine 7; `redmine70-migration` is what
  goes live. No backports, no cherry-picks to the default branch, no code paths only for 5.1.
- **prepend, never alias_method** (Jan, 2026-10-07) on a core method other plugins also patch.
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why). Push after every
  commit, together with the updated status in this file: a cloud session can stop at a usage
  limit, and work that is not pushed is lost with its container.
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL, alone and with the
  other GEOxyz plugins (numbers in this file); boot, production-like eager load, migrations up/down OK.
- Every function in the inventory exercised end to end on a real running Redmine, with and
  without permissions and on its failure paths; `./.codex/e2e.sh` green; screenshots looked at,
  committed in `docs/e2e/` and listed.
- Review done: your own, and the OpenAI review when the key is present, every finding resolved
  in `docs/reviews/`.
- No new failure when run together with the other GEOxyz plugins.
- "After the upgrade" lists every action production needs; "Status" is current.


## Analysis report (2026-10-06, Dutch)

# redmine_parent_child_filters
- Gebruikte branch: main @ d680607 (2026-10-01) - plugin id redmine_parent_child_filters, versie 1.1.0
- Upstream: geen (eigen plugin, github.com/jcatrysse/redmine_parent_child_filters)
- Fork t.o.v. upstream: n.v.t.
- Andere relevante branches: `origin/claude/codex-script-fixes` @ 6395797 (2 commits voor op main, 2026-10-04): alleen `.codex/*.sh` testscripts, CHANGELOG en `spec/spec_helper.rb` (`fail_if_no_examples`); geen plugin-runtimecode. Gelezen en getest, niet gewijzigd.
- Geen migraties, geen gem-afhankelijkheden buiten test (`rspec`, `rspec_junit_formatter`).

## 1. Werkt out of the box op Redmine 7?   JA
Harness `redmine_parent_child_filters@origin/main` (1006-090143-s2):
- OK bundle, boot (1.1.0), eager load, plugin migrations dev+test
- OK rspec: 728 examples, 0 failures, 2 pending (beide "MySQL only", terecht overgeslagen op PostgreSQL)
- OK smoke: 60/60 pages+actions zonder serverfout (0 plugin routes); geen deprecation warnings.

`origin/claude/codex-script-fixes` (1006-090415-s2): identiek resultaat (728 examples, 0 failures, 2 pending; smoke 60/60). De branch verandert niets aan het gedrag op Redmine 7.

## 2. Upstream sync?   GEEN UPSTREAM

## 3. Werkt na sync op Redmine 7?   n.v.t.

## 4. Complexiteit en blokkers   score 1
- Blokkers: geen. De plugin heeft al CI voor 5.0/5.1/6.0/6.1/7.0 en COMPATIBILITY.md claimt 7.0; dat klopt.
- Gepatchte core-methodes, vergeleken 5.1 vs 7.0: `QueriesHelper#filters_options_for_select(query)` (prepend, roept super aan met tijdelijk verborgen eigen filters; core-methode inhoudelijk ongewijzigd behalve `:"field_#{$1}"`), `IssueQuery#initialize_available_filters` (4x prepend), `Issue#project=(project, keep_tracker=false)` en `Issue#after_project_change` (prepend; beide nog aanwezig met dezelfde signatuur in 7.0).
- Stille breuken: geen gevonden. De 7.0-filters `author.group`/`author.role` vallen onder de core-groepering; de plugin groepeert alleen zijn eigen filters.
- Overlap met Redmine 7 core: geen.
- Pairwise (statisch): `IssueQuery#initialize_available_filters` wordt ook gepatcht door redmine_issue_field_visibility en redmine_itil_priority (beide alias_method-ketens). Laadvolgorde is alfabetisch (issue_field_visibility, itil_priority, parent_child_filters): de alias-ketens worden vóór de prepends gezet, wat de veilige volgorde is. Het omgekeerde (alias_method ná een prepend op dezelfde methode) geeft SystemStackError; de coördinator moet dit in de integratietest bevestigen.
- Open werk voor ansif: geen voor de migratie. `claude/codex-script-fixes` kan los gemerged worden (alleen tooling).

## Branch redmine70-migration
- Niet aangemaakt: geen fixes nodig.
- Eindresultaat harness (bijgewerkte harness van 09:26, `origin/main`, 1006-093205-s2): OK bundle, boot 1.1.0, eager load, migrations dev+test, OK rspec 728 examples 0 failures 2 pending, OK smoke 60/60.
- Rollback migraties: n.v.t. (geen migraties)


## Aanvulling coordinator
Branch `redmine70-migration` is wel gepusht, als startpunt zonder commits: gelijk aan de gebruikte branch (d680607). Fixes die hierboven als diff staan, zijn nog niet gecommit.


## Aanvulling coordinator (2026-10-06, tweede ronde)
Hertest op origin/main d680607 (= redmine70-migration): PostgreSQL rspec 728 examples, 0 failures, 2 pending (MySQL-only); MariaDB 10.11 rspec 728 examples, 0 failures, 1 pending; boot, eager load en smoke 60/60 op beide.

