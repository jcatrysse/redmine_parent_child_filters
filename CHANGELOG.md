# CHANGELOG

## 1.0.0

First release considered ready for production, and the first that starts on
Redmine 6.1 and 7.x at all. It closes a SQL injection, fixes four filters that
returned the wrong issues, adds six filters, and changes the meaning of two
existing ones. The test suite now boots Redmine and runs every filter against a
real database, on five Redmine versions and two database engines.

Everyone on 0.2.0 or earlier should upgrade. Read **Breaking** first: two saved
query shapes change meaning.

### Breaking
* **`child_tracker` with "is not" changed meaning.** It used to select issues
  *having a child of another tracker*; it now selects issues *having no child of
  that tracker*, matching `child_status`, `tree_child_tracker` and
  `tree_child_status`, which already worked that way. Issues with no children at
  all now match, as they do for every other "is not" filter in Redmine.

  A saved query that relied on the old behaviour keeps working by switching the
  filter to **is** and selecting the other trackers instead.

  The two child filters are also no longer folded into a single "same child"
  subquery once either of them is set to "is not"; folding a negation would be
  ambiguous. While both ask for a match, the "same child" rule is unchanged.

* **"any" and "none" mean something now, and it is not what they used to mean.**
  Redmine offers both operators on every list filter, and this plugin never gave
  them a meaning. They answered three different ways depending on the filter —
  `parent_tracker` matched nothing for both, `parent_status` matched everything for
  both, `child_status` matched the same rows for both — so the interface offered a
  choice that made no difference, and none of the three answers was right.

  They now follow the rule already documented for "is not": a filter over a set of
  relatives asks whether one exists. `Subtasks: Status` **any** selects issues that
  have a subtask; **none** selects issues that have none. For the root and
  whole-tree filters the set is never empty, since every issue has a root and
  belongs to a tree, so **any** is every issue and **none** is no issue — which is
  what the `root` filter already did.

  Two consequences worth stating. `root_status` **any** used to mean "is not its own
  root", a different question — "has a parent" — which Redmine answers itself with
  `Parent task: any`; that meaning is gone. And a saved query using **any** or
  **none** on any of these filters returns different rows than before, because it
  previously returned all rows or none.

* **A tracker filter and a status filter over the same set of relatives now
  describe the same relative.** `a_parent`, `tree`, `tree_parent` and `tree_child`
  used to evaluate their two filters independently, so "is under an open Epic"
  matched an issue having an Epic ancestor and, separately, an open ancestor.
  `child` already behaved this way and now `a_child` does too.

  A saved query that relied on the old behaviour has no direct replacement; the
  two conditions were never meant to describe different relatives.

### Added
* `mentioned` and `involved_or_mentioned`, matching issues where a user is mentioned
  with @login in the description or in a note the current user may read. Redmine
  records mentions without storing them, so the filter reads the text: a LIKE
  narrows the rows down and a regular expression then applies the word boundary,
  so "@jan" does not match "@jansen" or an address containing the login. Private
  notes are excluded through Redmine's own visibility condition.

  The condition is a correlated EXISTS, which scales with the issues the rest of
  the query leaves to check rather than with the size of the journals table. See
  the README for measurements and for what to do on a large instance.

  `involved` deliberately stays free of mentions so that it remains a cheap
  indexed lookup; `involved_or_mentioned` is the combined filter.

* `involved`, a single filter matching issues where the chosen principal is the
  assignee, the author or a watcher. Redmine joins filters with AND and offers no
  OR between them, so the query could not be expressed before: three separate
  filter rows demand all three roles at once.

  The OR lives inside one filter rather than in Query#statement, which leaves
  saved queries, the REST API and every other query class untouched. The watcher
  part reuses Redmine's own condition, so watchers of other users stay behind the
  view_issue_watchers permission, and `<< me >>` covers the groups you belong to.

* Redmine's status history operators `has been`, `has never been` and `changed from`
  now work on every status filter this plugin adds. They were offered by the
  interface and silently ignored. The journal lookup is Redmine's own, so it
  respects the permission to read private notes.
* `a_child_tracker` and `a_child_status`, matching an issue on any descendant at
  any depth. They are the mirror image of the existing `a_parent_*` pair and close
  the one asymmetry in the filter set: the hierarchy could be queried upwards at
  any depth, but downwards only one level at a time.

  `child_*` sees direct children only and `tree_*` covers the whole tree, so
  "has an open issue somewhere below this one" was not expressible before.

  Both follow the child filter rules: "is not" means "has no matching descendant",
  and the pair describes the same descendant while both ask for a match.

### Fixed
* **Four structural subqueries still read the issues table without scoping it, so a
  hidden relative could change a visible issue's answer.** The visibility work
  elsewhere in this release covered eight of the twelve subqueries and stopped short
  of the four that ask whether a relative *exists* at all — which is the sharpest
  form of the same leak, because the answer is exactly one bit about an issue the
  user may not see. `tree_has_parent_or_child` scoped neither the row nor the child
  it looked for; `pcf_tree_parent_subquery` let an invisible child prove that a
  visible parent is a parent; `pcf_tree_child_subquery` did not scope the parent
  whose `root_id` it returns; and `pcf_standalone_subquery` counted invisible
  children, so an issue whose only child was hidden was not standalone.

  "Has a parent" now means "has a parent you can see", tested the same way on both
  sides. The regression specs assert indistinguishability rather than absence: two
  issues differing only in a hidden relative have to land on the same side of the
  filter, whichever side that is. Against the previous code they fail in both
  directions — a hidden child both added an issue to *has a parent or a child* and
  removed it from *tree: child tracker* — which is what makes them regression specs
  rather than decoration.

  Measured cost of closing it, on 20 000 issues: 16 ms → 161 ms on PostgreSQL and
  171 ms → 930 ms on MySQL for *has a parent or a child*, with the *tree* parent and
  child filters 2 to 5× dearer. Stated in the readme rather than hidden, because
  these are now the plugin's expensive filters and an administrator deserves to know
  which ones and why.
* **"any" and "none" on the four tree parent/child filters still observed a hidden
  parent.** Those operators do not carry a value, so they take a separate path, and
  that path asked `linked.parent_id IS NOT NULL` — true of an issue whose parent sits
  in a project the user cannot open. So a visible issue with a hidden parent was
  treated differently from an identical issue with no parent, on eight filter and
  operator combinations, while the same question asked with a value was answered
  correctly.

  Both callers now share one subquery, `pcf_visible_link_subquery`, rather than each
  building its own — two builders for one question is how they drifted apart in the
  first place.

  The root cause was in the tests, not the SQL: the previous round asserted every
  operator on one filter family and only the value operator on the other four, so
  eight combinations were never executed and a green suite said nothing about them.
  The visibility specs now cross the operators with the filter families, and against
  the previous code the matrix fails on exactly those eight.
* **`has a parent or a child` read an unrecognised value as "no".** The value comes
  from a select offering exactly `1` and `0`, so anything else is a corrupted saved
  query or a hand written url — and answering the opposite question is worse than
  answering none. It now fails closed like every other filter here: nothing for a
  positive operator, everything for a negation.
* **Principal ids were read with core's `scan(/\d+/)`.** That turns `1 OR 2` into
  principals 1 and 2, and `user-123` into principal 123. Only digits ever reached the
  SQL, so it was never a hole, but the plugin's own value parser already spells out
  why the reading is wrong: a corrupted saved query then quietly answers about real
  people. Hierarchy ids were already strict; principals now use the same parser, so
  there is one rule rather than two. A security spec that pinned the permissive
  behaviour as desired has been rewritten to assert the strict one.
* **`pcf_select_ruby` returned 1 when it selected a Ruby quietly**, because its last
  statement was `[ "$mode" = install ] && echo ...`. Under `set -e` that killed
  `test_plugin.sh` and `benchmark.sh` before they ran anything, with no output at all
  — so the documented way to run the suite locally was broken for everyone with mise
  installed. CI never saw it because CI has no mise, and ShellCheck does not look at
  what a function returns. `.codex/test_scripts.sh` now runs the helpers and checks
  their exit status across mise/no-mise and every mode, and the lint workflow runs it.
* **The depth based parent filters silently answered a different question when
  several depths were selected.** They collapsed the selection onto the smallest
  depth, so picking *(1) Task* and *(3) Epic* looked for a Task or an Epic one
  level up and ignored the 3. Each depth is now evaluated at that depth and the
  results are OR-ed, which is what the selection says.

  The javascript that greyed out options of a second depth is gone with it: the
  restriction existed to hide the bug. The remaining inline script, which kept the
  two depth settings in order, is gone too now that the server does that itself —
  so the plugin ships no JavaScript at all and adds nothing to a strict CSP.
* **Redmine 6.1 and 7.x would not start.** `QueriesHelper.include IssuesHelper` raised
  `ArgumentError: cyclic include detected`, because core added `include QueriesHelper`
  to `IssuesHelper` in 6.1.
* **Filter values were interpolated into SQL unescaped.** Any user able to open the
  issue list could inject SQL through `v[<filter>][]`, and the payload was persisted
  in saved queries. All values are now reduced to integers.
* **A visible issue could reveal the tracker, status or status history of a relative
  the user is not allowed to see.** The outer query is scoped by Redmine, but the
  hierarchy subqueries read the whole issues table, so `Subtasks: Status is Closed`
  answered on children in projects the user cannot open, and on issues marked
  private. No id, subject or project ever leaked — the answer did, which is enough
  to learn "this issue has a closed Bug below it".

  Every relative subquery is now scoped with `Issue.visible_condition` for the
  current user, aliased the way Redmine core aliases it for its own
  `total_estimated_hours` column. For the depth filters every level of the chain
  must be visible, not only the level being asked about, or an invisible issue in
  the middle would still connect the two ends. "Is not" keeps meaning "there is no
  such relative", so an issue whose only child is invisible answers the same way an
  issue with no children answers.

  A user who can see both ends sees no change at all.
* **A value that was not an id was read as one.** `pcf_id_list` scanned for digit
  runs, which is Redmine core's own idiom, so `1 OR 2` became `1,2` and `user-123`
  became `123`. Only digits ever reached the SQL, so this was never injectable, but
  a mistyped url or a saved query from an older version quietly returned real rows.
  A value is now a whole positive id or a comma separated list of them, or it is not
  a value: it is dropped, and a filter left with nothing usable matches nothing.
* **`child_status` with "is not" returned the wrong issues.** The subquery selected
  `parent_id` without excluding NULLs, which makes `NOT IN` evaluate to UNKNOWN for
  every row; the filter silently degenerated into "has no parent".
* **The depth based filters could be used to exhaust the server.** A crafted depth
  generated an unbounded number of joins, and a value without a depth raised a 500.
  Malformed values are now ignored and the depth is bounded — see below for the
  ceiling that bounds the bound.
* **The depth ceiling was itself unbounded.** The settings form offered 1 to 10, but
  the stored value was only floored at 1, so a `max_depth` written through the REST
  API or the console was accepted verbatim: a crafted filter value then produced one
  self join per level. Measured before the fix, `max_depth` of 10 000 and a filter
  value asking for level 9999 built 9999 joins and a 686 kB SQL statement. There is
  now a single `MAX_DEPTH = 10` that both the form and the query read, and every
  stored value — missing, empty, negative, reversed, fractional or absurd — is
  normalised against it in one place.
* Reversing the two depth settings no longer depended on JavaScript to correct it.
  The values are normalised where they are read, so the filters behave the same with
  scripting disabled, and the settings page shows the range that will actually be
  used.
* The "Add filter" dropdown no longer loses Redmine's own filter groups. Core's
  implementation is reused instead of a copy taken from Redmine 4.x.
* `ActionView::Base` and `IssuesController` are no longer patched globally; core
  already exposes `QueriesHelper` to both.
* Date filter operators are no longer mutated in place on the shared
  `operators_by_filter_type` hash.
* A filter setting explicitly stored as `'0'` now disables the filter, in the
  query and in the settings form alike.
* **Redmine 5.0 raised `Unknown query operator ev`.** 5.0 has no status history
  operators, so offering `has been` / `has never been` / `changed from` on the
  plugin's status filters produced a `QueryError`. The operators are now offered
  only where core supports them.
* The settings labels are now linked to the checkbox they toggle; clicking a
  label did nothing because the `for` attribute did not match the input id.
* Each checkbox now posts an explicit `0` when unticked, the way Redmine's own
  `setting_check_box` does. A browser sends nothing at all for an unticked box, so
  "off" used to be stored as the absence of a key rather than as a value, and the
  difference had to be interpreted everywhere it was read.
* The settings page says what a level means, in the interface rather than only in
  the readme: `1 = Parent task`, composed from Redmine's own `field_parent_issue`
  so it reads grammatically in all fifty languages without a sentence having to be
  translated into any of them.
* The settings partial no longer defines a method on the view class every render.
* **The mention filter missed `@jsmith.`** — a mention at the end of a sentence, which
  is how most of them are written. The word boundary was one character class doing
  three jobs, so a dot after the login read as part of the login. Measured against
  Redmine's own `MENTION_PATTERN` over a corpus of forty texts it disagreed on ten;
  it now disagrees on three, each pinned by a spec and documented in the readme.
* **On MySQL the mention filter depended on the column collation.** `REGEXP` follows
  the collation, so on a column declared `utf8mb4_bin` — what an instance ends up with
  after a migration from an older MySQL — `@JSmith` stopped matching the login
  `jsmith`, while PostgreSQL and Redmine's own notification matched it. The pattern
  now carries an inline `(?i)`, which no collation can override.
* **The hierarchy filters would silently replace a core filter of the same name.**
  `add_available_filter` overwrites whatever sits under the name it is given. The
  people filters already stepped aside on a collision; the 20 hierarchy filters did
  not, so a future Redmine shipping, say, its own `child_status_id` would have had
  its meaning quietly changed. All 23 filters now register through one path that
  refuses to overwrite and logs the reason once per process.

### Translations
* **All 50 languages Redmine ships are now translated**, up from 7. Every locale
  carries all 30 keys; the release before this one left 43 languages showing raw
  keys such as `label_filter_child_status_id` in the filter dropdown.
* The labels are composed from Redmine's own nouns per language, so a filter reads
  with the words that language already uses elsewhere in the interface: German
  *Untergeordnete Tickets: Status*, Japanese *子チケット：ステータス*, Dutch
  *Subtaken: Status*.
* One label per filter instead of two. The settings checkbox reuses the filter's
  own label, so a filter cannot be named one thing in the dropdown and another in
  the administration screen.

* **The "is not" operator on dates was never tested.** It has been in the plugin
  since 0.0.3 and had no coverage at all. It turns out to be correct, including the
  NULL case and date custom fields, but its reach was documented wrongly: see
  Changed.

### Changed
* The documented scope of the date "is not" operator is now accurate. Redmine
  attaches operators to a filter *type*, so the operator reaches every `:date`
  filter — start date, due date **and every date custom field**, on every query
  class — not just "start_date and end_date" as the readme claimed. `end_date` is
  not even a filter name; the field is `due_date`. Redmine's date-time filters
  (`created_on`, `updated_on`, `closed_on`, `spent_on`) are typed `:date_past` and
  are untouched. Narrowing the operator to two fields would mean inventing a filter
  type Redmine's own javascript cannot render a value widget for, so the reach is
  documented rather than fought.
* Minimum supported Redmine is 5.0. Tested against 5.0, 5.1, 6.0, 6.1 and 7.0.
* `initialize_available_filters` is patched with `Module#prepend` instead of an
  `alias_method` chain.
* The plugin ships no migration, so `redmine:plugins:migrate` is no longer needed.
* The `root` filter states its degenerate operators explicitly: "any" matches
  every issue and "none" matches none, since every issue belongs to a tree, its
  own if it has no relatives.
* The 20 hierarchy filters are registered from one list instead of 20 near
  identical blocks, and the setting key and translation key are derived from the
  filter name. Adding a filter is now one line plus its options, and the "Add
  filter" dropdown groups it automatically because the grouping reads the same
  list.
* Removed an empty `config/routes.rb`; the plugin adds no routes.

### Performance
* **On MySQL, a depth filter past level six never returned.** Each level is one self
  join and the visibility scoping added a table per level, and MySQL's optimiser
  searches join orders exhaustively up to `optimizer_search_depth`, which defaults to
  62. Measured on the empty fixture tables: 0.25 s at eight tables, 1.02 s at ten,
  12.75 s at twelve, no answer at all at fourteen — while PostgreSQL and MariaDB
  planned every one of them in milliseconds. The chain has exactly one sensible join
  order and it is the order the plugin writes it in, so it now says so with
  `STRAIGHT_JOIN` on MySQL, scoped to that one subquery. Level 10 went from never
  returning to 0.01 s.
* The same measurement repeated on the benchmark dataset rather than on empty tables,
  because a hint that fixes planning cost need not fix execution cost. On 20 000
  issues against MySQL 8.0.46 the hinted query costs 175 ms at level 10 and is flat
  from level 1 to level 10; with the hint removed the same query takes 5.1 s at level
  6, 49.8 s at level 8 and had still not answered after nine minutes at level 10.
* **The benchmark harness itself was measuring the wrong thing on MySQL and MariaDB.**
  It wrote `root_id` with `((id - first) / CHAIN) * CHAIN`, which is integer division
  on PostgreSQL and floating point division on the other two — so every child became
  its own tree root there, and the tree filters, which key on `root_id`, measured
  almost nothing. The dataset looked perfectly healthy: 20 000 issues, 15 000 with a
  parent. It now uses modulo arithmetic both engines read alike, and asserts the shape
  of the tree it built before timing anything. The readme's MySQL figures are
  re-measured; its MariaDB column is gone rather than restated from a run that cannot
  be trusted.
* Timings are now the median of five runs rather than one. A single measurement of the
  heavier tree filters varied by half between runs of identical code, which is more
  than the differences a reader would draw conclusions from — and it did produce two
  wrong conclusions before this changed.
* The mention filter measured as the selection grows, which is the question a single
  regex over every selected login raises: 266 ms at one principal, 363 ms at 100,
  749 ms at 500 and 1 180 ms at 1 000, on 20 000 issues and 100 000 journals against
  MySQL 8. Linear, no engine limit reached, no error at any size — so no cap on the
  selection, because a limit would be complexity bought with a guess instead of a
  measurement. `PCF_BENCH_PRINCIPALS=1` reproduces it.
* A reproducible benchmark, `./.codex/benchmark.sh`. It seeds a representative
  dataset (20 000 issues in trees of four, 100 000 journals by default), times every
  filter family with the Rails query cache off, writes the `EXPLAIN` plans to
  `tmp/benchmark/` and reports whether the indexes the filters rely on are present.
  They all ship with Redmine, so the plugin needs none of its own. The readme's
  numbers are now something a reader can reproduce rather than take on trust.
* The measured price of scoping the relative subqueries by visibility: on PostgreSQL
  the cheapest hierarchy filters roughly double, from ~8 ms to ~16 ms on 20 000
  issues; on MariaDB the difference disappears into run-to-run noise. Stated as a
  measurement rather than an opinion — `PCF_BENCH_NO_VISIBILITY=1` reproduces it.
  Reducing it further would mean splitting core's visibility SQL into its project
  level and issue level halves, which is exactly the kind of parsing that breaks on
  the next Redmine release.
* The mention filters use one regular expression for the whole selection rather
  than one comparison per principal, so their cost no longer grows with the
  number of principals. On 20 000 issues and 200 000 journals, PostgreSQL went
  from 1038 ms to 273 ms for twenty one principals, and is now flat.
* The logins behind a mention filter are resolved once per request rather than
  once per statement build.

### Documentation
* `TRANSLATING.md` explains how the labels are composed from Redmine's own nouns per
  language, why a few locales legitimately contain English words (Redmine's own
  `hr.yml` has them, and "fixing" them here would make the filter disagree with the
  field name shown two lines higher), how to avoid needing new prose at all, and the
  two YAML traps — `no:` parsing as `false`, and values that change meaning unquoted.
* The readme documents rollback and the upgrade from a version before 1.0.0, with a
  read-only console snippet that lists the saved queries whose filters changed
  meaning. Rollback is complete by removing the folder: no migration, no column, no
  index, nothing stored outside the plugin's own `settings` row.
* A bug report template that asks for the four version numbers, the database and its
  version, the query, optionally a query plan, and whether a "missing" issue might be
  a visibility question — the answers that make a filter report reproducible at all.

### Compatibility
* `COMPATIBILITY.md` lists every assumption the plugin makes about Redmine's
  internals — the return shape of `available_filters`, the five argument form of
  `sql_for_field`, the tables `Issue.visible_condition` names, the
  `@available_filters` ivar the dropdown patch swaps — with what breaks if each one
  moves. `spec/core_contract_spec.rb` asserts all of them, so an upgrade that changes
  one fails a named example instead of producing wrong SQL somewhere downstream.
* Two calls through `send` are gone: `sanitize_sql` has been public since Rails 5.2,
  which is older than the oldest Rails this plugin supports. The two remaining
  non-public assumptions are documented with the public alternatives that were tried
  and why each was worse.

### Testing
* The spec suite now boots Redmine and executes every filter against a real
  database. The previous suite asserted on SQL strings against stub objects and
  could not detect invalid SQL, NULL semantics or the injection above.
* CI runs the matrix {5.0, 5.1, 6.0, 6.1, 7.0} x {PostgreSQL, MySQL, MariaDB} on
  every push and every pull request. MySQL and MariaDB are separate axes because
  they are not interchangeable here: `REGEXP` case sensitivity follows the
  collation and the two ship different defaults, which is what the mention filter
  leans on. The readme claimed MariaDB support that nothing tested.
* The database a job needs is started by `.codex/start_database.sh` rather than
  declared as a `services:` block. GitHub cannot start a service container
  conditionally, so three engines meant every job pulled all three images — 48 pulls
  per push — and the first run of the three-engine matrix duly failed on a MariaDB
  job that could not pull the PostgreSQL image it was never going to use. Now one
  job pulls one image, with the pull retried three times, and a failure to become
  ready prints the container log instead of a bare timeout.
* A weekly run repeats the whole matrix plus Redmine trunk. The per-push workflows
  pin each branch as it stood when the plugin last changed, while the clone script
  always takes the branch tip, so the weekly run is what catches a Redmine patch
  release that breaks a filter. Nothing in it is allowed to fail quietly: a red
  scheduled run mails the repository owner, which a `continue-on-error` trunk job
  would not have. The workflows are thin callers around one reusable workflow,
  which in turn runs the same `.codex` scripts a developer runs locally, so CI
  and a laptop cannot drift apart.
* Every GitHub Action is pinned to a commit SHA rather than a tag, with the version
  in a trailing comment. A tag can be moved to point at other code; a SHA cannot.
  Dependabot bumps the pin and the comment together, monthly, so the pins do not
  quietly rot — pinning without that is worse than not pinning at all.
* Redmine's own database credentials never appear in this repository. The fixed
  `redmine`/`redmine` pair in the scripts and the workflow is labelled as what it
  is: throwaway credentials for a throwaway container.
* A lint workflow runs RuboCop (configured to match Redmine's own style
  decisions), ShellCheck on the scripts, and a parse of all 50 locale files.
  Psych reads a bare `no:` key as the boolean `false`, which is exactly the kind
  of mistake that only shows up in Norwegian.
* A spec forces `Rails.application.eager_load!`. Redmine 6 and later eager load
  every plugin's `lib/` in production but not in test, so a load order mistake
  used to pass the suite and break a production boot.
* A spec asserts that every hierarchy filter reaches the plugin's group in the
  "Add filter" dropdown, and that the people filters stay out of it.
* The deepest depth filter is now run under a deadline the *database* enforces.
  Without one, a planner blow-up does not fail a spec, it hangs it — the MySQL problem
  above cost a CI job half an hour and left nothing useful in the log. The first
  attempt used `Timeout.timeout`, which turned out not to bound anything: Ruby cannot
  interrupt a query blocking inside the driver, so the exception is only delivered
  once the query returns. Measured on MySQL 8, `Timeout.timeout(3)` around a 30 second
  query returned after 30.0 seconds, and the depth-10 query above kept the server busy
  for nine minutes after the spec had given up on it. `SET SESSION max_execution_time`
  (`max_statement_time` on MariaDB, `statement_timeout` on PostgreSQL) returned the
  same query in 3.0 seconds, so that is what the spec uses. A further spec asserts that
  the deadline is really enforced, since one that silently fails to apply looks
  exactly like a fast query.
* `PCF_DB=mysql` now installs `mysql-server` rather than Ubuntu's
  `default-mysql-server`, which is MariaDB. Asking for MySQL and silently getting
  MariaDB is how the problem above survived ten local runs: the two share the mysql2
  adapter but not their optimisers. The script now prints the version the server
  reports and warns when it disagrees with the engine that was asked for.
* The settings page warns, where the mention filters are switched on, that they read
  issue text and so cost more than the rest. An administrator ticking that box sees
  the settings page, not the readme. The sentence is translated in all fifty locales
  rather than left in English in forty-nine of them, and a spec renders the page in a
  second language to prove it arrives translated.
* Accessibility of the settings page is asserted in the integration spec: one id per
  input and no id twice, every label pointing at an input that exists, a legend per
  fieldset, and a long translation rendered intact. No browser stack was added for
  it — the plugin ships no JavaScript, so there is no client behaviour left for one
  to exercise, and a duplicate id is exactly what does break in practice.
* A spec asserts that every filter has an administration switch, that the switch
  appears in the settings form, and that each one can be turned off on its own.
* The injection specs cover the principal filters by asserting that a crafted
  value produces byte identical SQL to its sanitised equivalent, and that a login
  holding LIKE wildcards or regular expression metacharacters stays a literal.
* A spec runs a filter through every path it takes in production: the issue list,
  the Gantt, the calendar, CSV, PDF, Atom, the REST API and a stored query read
  back from the database.
* A spec runs all 23 filters with every one of their operators, 96 queries in all,
  as a user who is not a member of a private project, and asserts that no issue
  from that project is ever returned.

## 0.2.0 (ALPHA version: do not use in production)
* Add tree-wide filters to surface complete hierarchies alongside existing parent/child filters.
* Document and translate the new tree filter options and settings toggles.
* Introduce RSpec test coverage for the full filter suite.
* Introduce GitHub actions.

## 0.1.0
* Optimize UX for `specific depth` filters.

## 0.0.5
* Filter on `parent_tracker` (specific depth)
* Filter on `parent_status` (specific depth)
* Prefix plugin name with `Redmine`

## 0.0.4
* Filter on `parent_tracker` (any depth)
* Filter on `parent_status` (any depth)
* Add plugin settings to enable filters

## 0.0.3
* Filter on `root`
* Filter on `root_tracker`
* Filter on `root_status`
* Operator `not equal to` on `start_date` and `end_date`
* Resolved issue: `SystemStackError (stack level too deep)`  
  Converted `initialize_available_filters` to use `alias_method` 

## 0.0.2
* Filters `child_tracker` and `child_status`, when combined, are now considering the same child

## 0.0.1
* Initial commit
* Filter on `parent_tracker`
* Filter on `parent_status`
* Filter on `child_tracker`
* Filter on `child_status`
