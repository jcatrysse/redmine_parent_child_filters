# Redmine 7 migration: redmine_parent_child_filters

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. Report to me in Dutch at the end.

This file is the plan and the memory of that work. Update it as you go: verdicts, results,
what is left. Written 2026-10-06 from a measured analysis (report at the bottom).

## Status

| | |
|---|---|
| Plugin id | `redmine_parent_child_filters` |
| GEOxyz runs today | `main` |
| Upstream | geen |
| Runs on Redmine 7 as is | JA |
| Upstream sync | GEEN UPSTREAM |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 1 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz + latest 7.0-stable), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16 and MariaDB 10.11 |
| Branch head when this file was written | `d680607` |

## Already on this branch

- nothing: the branch equals the branch GEOxyz runs today.

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Open items from the analysis** (Dutch; where they repeat a priority item, the priority item wins)

1. Geen migratiewerk; claude/codex-script-fixes (alleen .codex-tooling) kan los gemerged worden
2. Integratietest: volgorde alias_method (issue_field_visibility, itil_priority) vs prepend (deze plugin) op IssueQuery#initialize_available_filters bevestigen

**Checks**

3. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL AND MariaDB, and once on 5.1-stable if the branch is meant to stay 5.1-compatible.
4. Check Redmine 7 webhooks against this plugin (see "Rules"), and note the result here even if nothing is needed.
5. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots).

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply. While migrating, hold the code you touch to the rules below; list larger quality problems you find in the work list instead of fixing them in passing.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- None known. Add here what the session finds.

## How to test

This repo already has its own `.codex/` scripts (older variant). Read their headers and use them; check they accept `7.0-stable-GEOxyz` (clone from https://github.com/jcatrysse/redmine.git) and MariaDB. The shared variant from the other plugin repos may replace them if that is simpler.

The coordinator's harness (`plugin-check.sh` in the migration kit, kept outside this repo) adds a
browser smoke test of every page the plugin adds and runs all GEOxyz plugins together; the
results quoted in the analysis come from it.

## How the migration session works (same for every plugin)

1. **Start**: `git fetch && git checkout redmine70-migration && git pull`. Read this whole file,
   including the analysis report at the bottom. Do not reopen decisions recorded here.
2. **Baseline**: set up Redmine 7.0-stable-GEOxyz and run the plugin's tests on PostgreSQL and
   on MariaDB (see "How to test"). Write the numbers here before you change anything.
3. **GEOxyz changes**: go through the table above, one item at a time. Each kept or re-made change
   is its own commit with a test that proves it. Record the verdict in the table.
4. **Work list**: then the numbered list, in order. One concern per commit.
5. **Portability**: everything must run on Redmine's supported databases (PostgreSQL,
   MySQL/MariaDB; SQLite where the plugin already supports it). Migrations must be reversible and
   are run down and up on PostgreSQL and MariaDB.
6. **Browser**: start a Redmine 7 with this plugin, exercise every feature as admin and as a
   normal user with and without the plugin's permissions, and save screenshots (before on 5.1 or
   the old branch, after on 7.0) where behaviour or layout matters.
7. **Together**: run with the other GEOxyz plugins installed (the migration kit's harness, or
   `RMP_EXTRA_PLUGINS`). A failure that only appears in combination is a finding to record here.
8. **After the upgrade**: anything the production upgrade must do for this plugin (data fixes,
   settings, cron, files, removed features) goes into the section "After the upgrade".
9. **Finish**: update "Status" and the work list in this file, push `redmine70-migration`, and
   report: what changed, test numbers on both databases, what is left, what needs Jan.

### Stop and ask Jan when
- a GEOxyz change would be lost or behave differently for users;
- a new gem, a new setting with user impact, or a schema change not required by Redmine 7 seems needed;
- the change would send data to an external service;
- upstream and GEOxyz disagree on behaviour and both are defensible.

## Rules

- **Target**: Redmine 7.0-stable-GEOxyz (https://github.com/jcatrysse/redmine), Rails 8.1, Ruby 3.3+.
  Core sources for comparison: branches `5.1-stable`, `6.1-stable`, `7.0-stable`, `7.0-stable-GEOxyz`.
- **Evidence**: never report a test, lint or browser check as passed without having seen it.
  Quote the summary lines. "Should work" is not a result.
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
  `ContextMenus::*Controller`, Loofah-based text formatting, Chart.js as an ES module.
  The breaker list is in the migration kit's CHECKLIST.md.
- **Locales**: keep the locales the plugin ships in sync; translate a new key by matching the
  closest existing key in the same file, not from scratch; do not add new languages.
- **5.1 compatibility**: prefer fixes that also run on Redmine 5.1 so they can be merged early;
  say so when a fix cannot.
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why).
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL and MariaDB
  (numbers in this file); boot, production-like eager load, migrations up/down OK.
- Every feature verified by hand on Redmine 7; screenshots listed.
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

