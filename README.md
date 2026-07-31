# Redmine Parent Child Filters Plugin

Advanced issue filters for Redmine, in two families:

* **hierarchy** — filter on the `tracker` and `status` of an issue's parents, children,
  ancestors, descendants, root or whole tree;
* **people** — filter on who is involved (assignee, author or watcher) or who is
  mentioned with `@login`, in one filter row rather than one per role.

No database migration, no patched Redmine core files.

Link to Redmine plugin page: [Redmine Parent Child Filters Plugin](https://www.redmine.org/plugins/redmine_parent_child_filters)

## Compatibility

Redmine 5.x, 6.x and 7.x, on PostgreSQL and MySQL/MariaDB.

Every push runs the whole suite on each combination below. "Tested" here means the
suite ran green against a real server of that engine, not that the version was read
off a compatibility list:

| Redmine branch | Rails | Ruby | PostgreSQL | MySQL | MariaDB |
|---|---|---|---|---|---|
| 5.0-stable | 6.1 | 3.1 | 16 | 8.4 | 11 |
| 5.1-stable | 6.1 | 3.2 | 16 | 8.4 | 11 |
| 6.0-stable | 7.2 | 3.3 | 16 | 8.4 | 11 |
| 6.1-stable | 7.2 | 3.4 | 16 | 8.4 | 11 |
| 7.0-stable | 8.1 | 3.4 | 16 | 8.4 | 11 |

A weekly run repeats the whole table plus Redmine trunk (`master`). The per-push
workflows test each branch as it stood when the plugin last changed, but
`redmine_clone.sh` always clones the branch *tip*, so the weekly run is what catches
a Redmine patch release that breaks a filter. It is allowed to go red — a failing
scheduled run mails the repository owner and blocks no pull request.

MySQL and MariaDB are separate columns on purpose. They are not interchangeable for
this plugin: `REGEXP` case sensitivity follows the collation and the two ship
different defaults, which is exactly what the mention filter leans on. MariaDB 10.11
has been verified as well, against the same suite.

Nothing here promises a future minor. What it promises is that the combination in the
table was run, and that a regression on any of them turns the pipeline red.

A plugin that adds filters cannot avoid leaning on the internals of `Query`.
[COMPATIBILITY.md](COMPATIBILITY.md) lists every place where this one does, what the
assumption is and what breaks if Redmine changes it; `spec/core_contract_spec.rb`
asserts each one, so an upgrade that moves any of them fails a named example rather
than producing wrong SQL.

Translated into all 50 languages Redmine ships, using each language's own words for
tracker, status, parent task and subtask so the filters read like the rest of the
interface. [TRANSLATING.md](TRANSLATING.md) explains how the labels are composed and
why some locales legitimately contain English words.

> Redmine 4.x is no longer supported. Releases before 1.0.0 do not start on Redmine 6.1 and later.

## Features
* **Root Level Filtering**: Enables you to filter issues based on the root-level attributes.
    * `root`
    * `root_tracker`
    * `root_status`

* **Immediate Parent Filtering**: Target issues based on their immediate parent attributes.
    * `parent_tracker`
    * `parent_status`

* **Any Parent Filtering**: Extend your filtering criteria to any level of the issue's ancestry.
    * `parent_tracker` (any parent)
    * `parent_status` (any parent)

* **Depth-Based Parent Filtering**: Filter on the ancestor a given number of levels up.
    * `parent_tracker` (with depth selection)
    * `parent_status` (with depth selection)

    Depths may be mixed: selecting *(1) Task* and *(3) Epic* matches issues whose direct
    parent is a Task **or** whose third ancestor is an Epic. Each selected depth is
    evaluated at that depth.

* **Child Level Filtering**: Directly target child issues with the following attributes.
    * `child_tracker`
    * `child_status`

    See *Filter semantics* below for how **is not** and combined filters behave.

* **Any Descendant Filtering**: The mirror image of *Any Parent Filtering*, looking down the
  subtree instead of up the ancestry, at any depth rather than at direct children only.
  Use it for questions like *"which epics still have an open issue somewhere below them?"*,
  which `child_*` cannot answer (direct children only) and `tree_*` answers too widely
  (the whole tree, including ancestors and siblings).
    * `a_child_tracker` (any descendant)
    * `a_child_status` (any descendant)

    See *Filter semantics* below.

> Questions about the shape of the hierarchy itself need no filter from this plugin.
> Redmine already answers them: `Parent task` **none** for top level issues, `Subtasks`
> **none** for issues without descendants, `Subtasks` **any** for issues that have some.

* **Tree Filters**: Surface the entire hierarchy when a parent/child match is found, and also show standalone issues (no parents or children) that match the same tracker or status criteria without changing the behavior of the existing filters.
    * `tree_has_parent_or_child` (can be used to filter standalone issues or issues with parents or children)
    * `tree_tracker` (tree-wide tracker match)
    * `tree_status` (tree-wide status match)
    * `tree_parent_tracker`
    * `tree_parent_status`
    * `tree_child_tracker`
    * `tree_child_status`

* **Involvement Filtering**: One filter answering *"issues where I am the assignee,
  the author or a watcher"*. Redmine joins filters with AND and has no OR between
  them, so this question cannot be asked with the stock filters: three separate
  rows would demand all three roles at once.
    * `involved` (assignee, author or watcher)

    Accepts `<< me >>` and any principal. An issue assigned to a group you belong to
    counts as yours, as it does for Redmine's own assignee and watcher filters.
    Watchers of *other* users stay behind the `view_issue_watchers` permission.

* **Mention Filtering**: Find issues where a user is mentioned with `@login`, in the
  description or in any note you are allowed to read.
    * `mentioned`
    * `involved_or_mentioned` (assignee, author, watcher or mentioned)

    Redmine records mentions but does not store them, so this searches the text. See
    *Mention filtering and performance* below before enabling it on a large instance.

* **Additional Operators**: Enhance your filtering capabilities with additional operators.
    * Operator **is not** on date filters. Redmine attaches operators to a filter
      *type* rather than to a filter, so this reaches every filter it types as `date`:
      **start date**, **due date** and any **date custom field**, on the issue list and
      on other query types alike. Redmine's date*-time* filters (created, updated,
      closed, spent on) use a different type and are unchanged.
    * Redmine's status history operators `has been`, `has never been` and `changed from`
      work on every status filter this plugin adds, not only on the issue's own status.

* **Settings**: The plugin provides a dedicated Settings menu where
    * Each filter can be enabled or disabled as per your requirements.
    * Additionally, you can configure the depth settings for depth-based filters.

    Level **1 is the direct parent**, 2 its parent, and so on. The two depth settings
    bound the levels the *Parent task (level)* filters offer. Each level costs one
    self join, so the plugin refuses anything above a hard ceiling of **10**,
    whatever the stored setting says — a value written straight to the database or
    through the REST API cannot turn one filter into an unbounded query. The
    effective range is shown next to the setting.

## Filter semantics

Two rules apply to every filter here, in every direction, so that a filter reads the
same way wherever you use it.

**"is not" means "there is no such relative".**
`child_tracker is not Test` selects issues having *no* Test child. An issue with no
children at all therefore matches, exactly as an unassigned issue matches
`assignee is not John` in Redmine. `has never been` works the same way: no relative
that has ever had that status.

To ask the opposite, *has a relative that is something else*, use **is** and select
the other values: `child_tracker is [Bug, Feature]`.

**A tracker filter and a status filter describe the same relative.**
`child_tracker is Task` combined with `child_status is Closed` finds issues having one
child that is a closed Task, not issues that happen to have a Task child and,
separately, some closed child. This applies to the pairs that range over a set of
relatives: `a_parent`, `child`, `a_child`, `tree`, `tree_parent` and `tree_child`.
As soon as one of the two is set to **is not**, they are evaluated independently,
because folding a negation into a shared subquery is ambiguous.

The `parent`, `root` and depth based filters need no such rule: there is only one
direct parent, one root and one ancestor at a given depth.

**"any" and "none" ask whether the relative exists**, not about its attributes.
`Subtasks: Status` **any** is "has a subtask", **none** is "has no subtask". The root
and whole-tree filters range over a set that is never empty — every issue has a root
and belongs to a tree — so there **any** is every issue and **none** is no issue.
The two always partition the issue list between them: every issue matches exactly
one of them, on every filter.

**"Exists" always means "exists as far as you can see."** Every question about a
relative — its tracker, its status, or merely whether it is there — is answered within
the issues Redmine lets the current user see. So *has a subtask* is false for an issue
whose only subtask sits in a project you cannot open, *has no parent or child* is true
for an issue whose only relative is hidden from you, and two colleagues with different
permissions can legitimately get different answers from the same saved query. That is
deliberate: the alternative is a filter that confirms the existence of issues you are
not allowed to know about. It also means the answer to an existence question is not a
fact about the database, and should not be read as one.

**`involved` is an OR, on purpose.** It is one filter holding
`author OR assignee OR watcher`, not three filters. Redmine ANDs filters together,
so the OR has to live inside a single filter; this is the same shape Redmine itself
uses for its watcher filter. "is not" negates the whole group, so it means
*not involved in any of those roles*, and unassigned issues are kept.

## Performance

The hierarchy filters compile to a correlated `EXISTS` (or a `UNION` of two, for the
tree filters), plus one self join per level for the depth filters. Every index they
need ships with Redmine — `issues(parent_id)`, `issues(root_id, lft, rgt)`,
`issues(tracker_id)`, `issues(status_id)`, `issues(project_id)` and
`journals(journalized_id, journalized_type)` — so the plugin adds no index and no
migration.

`./.codex/benchmark.sh` builds a representative dataset, times each filter family
with the Rails query cache off, writes the `EXPLAIN` plans to `tmp/benchmark/` and
reports whether those indexes are present. Measured on 20 000 issues in trees of
four and 100 000 journals:

| filter | PostgreSQL 16 | MySQL 8.0 |
|---|---|---|
| `child_status_id` | 17 ms | 63 ms |
| `a_child_status_id` | 15 ms | 99 ms |
| `a_parent_tracker_id` | 23 ms | 188 ms |
| `a_specific_parent_tracker_id` (level 3) | 62 ms | 165 ms |
| `tree_status_id` | 15 ms | 140 ms |
| `tree_has_parent_or_child` | 161 ms | 930 ms |
| `tree_parent_tracker_id` | 87 ms | 1249 ms |
| `tree_child_tracker_id` | 86 ms | 1535 ms |
| `involved_id` | 12 ms | 34 ms |
| `mentioned_id` | 118 ms | 148 ms |

Each figure is the median of five runs, not a single measurement: on the heavier tree
filters one run varied by half from the next on the same code, which is more than the
differences anyone should be drawing conclusions from.

**The structural tree filters are the expensive ones**, and knowing why matters more
than the numbers. *Has a parent or a child*, and the *tree* variants of the
parent/child filters, answer a question about a relationship rather than about a
column, and they only count relationships the current user can see. That costs a
join and a visibility test on each side of the relationship. Measured against the
same dataset, scoping them cost 10× on PostgreSQL (16 ms → 161 ms) and 2 to 5× on
MySQL (171 ms → 930 ms for *has a parent or a child*). It is not an optimisation
that was skipped: it is the difference between a filter that answers about issues
you may not see and one that does not. **any** and **none** on those four filters go
through the same subquery, so they cost the same as *has a parent or a child*. Adding a project or status filter alongside
brings them back to 130 ms on PostgreSQL and 210–440 ms on MySQL, which is the
lever to reach for on a large instance.

On MySQL the deepest levels of the *Parent task (level)* filters carry a join order
hint. Each level is one self join and the visibility scoping adds a table per level,
and MySQL's optimiser searches join orders exhaustively up to `optimizer_search_depth`,
which defaults to 62. The chain has one sensible join order and it is the one the
plugin writes, so `STRAIGHT_JOIN` says so. What that hint is worth, measured on the
same 20 000 issues:

| level | with the hint | without it |
|---|---|---|
| 3 | 169 ms | 173 ms |
| 6 | 155 ms | 5.1 s |
| 8 | 176 ms | 49.8 s |
| 10 | 175 ms | no answer in 9 minutes |

With the hint the cost is flat from level 1 to level 10, because the work is the same
and only the search for a plan was exploding. PostgreSQL and MariaDB plan every one of
these in milliseconds and get no hint.

Treat the absolute numbers as a shape, not a promise: they come from one container and
are useful for comparing two runs on the same machine, which is what the harness is
for. There is no MariaDB column because these figures were re-measured after a bug in
the harness itself (see below) and no MariaDB server was available to repeat them on;
the MariaDB axis of the test suite is unaffected and still runs on every push.

**One deliberate exception: `root_id`.** *Tree* takes an id you type, and turns it into
`issues.root_id IN (...)` without checking whether the issue with that id is one you
may see. That is exactly what Redmine core's own *Parent task* filter does with the id
you give it (`sql_for_parent_id_field` is `issues.parent_id IN (ids)`, unscoped), and
it is what makes pasting a known id to find your own subtasks work. The rows you get
back are still only the ones you may see; what is not checked is the id you supplied.
Every filter that asks a question *about* a relative — including `root_tracker_id` and
`root_status_id`, which read the root's columns — is scoped.

**What the visibility scoping costs.** Each relative subquery carries Redmine's
`Issue.visible_condition`, so a filter never answers about an issue you may not see.
`PCF_BENCH_NO_VISIBILITY=1 ./.codex/benchmark.sh` measures the price. On PostgreSQL
the cheapest hierarchy filters roughly double, from ~8 ms to ~16 ms. That is the cost
of a correct answer, and the lever for a large instance is the same as everywhere
else: scope the query.

**Mind the harness as well as the code.** The dataset builder wrote `root_id` with
`((id - first) / 4) * 4`, which is integer division on PostgreSQL and *floating
point* division on MySQL and MariaDB — so on those two engines every child became its
own tree root. The dataset looked right (20 000 issues, 15 000 with a parent) and the
tree filters, which key on `root_id`, measured almost nothing. The builder now uses
modulo arithmetic that both engines read the same way, and it asserts the shape of the
tree it built before anything is timed: a dataset that is wrong in a way nobody
notices still produces numbers, and those numbers end up in a readme.

**The mention filter as the selection grows.** All selected logins go into one regular
expression rather than one predicate each, so the question is how that scales.
`PCF_BENCH_PRINCIPALS=1 ./.codex/benchmark.sh` creates the users and sweeps it, on
MySQL 8 over 20 000 issues and 100 000 journals:

| principals selected | time | statement size |
|---|---|---|
| 1 | 266 ms | 0.6 kB |
| 100 | 363 ms | 5 kB |
| 500 | 749 ms | 25 kB |
| 1 000 | 1 180 ms | 50 kB |

Linear, about a millisecond per principal, no engine limit reached and no error at any
size. So there is no cap on the selection: at a thousand selected people the query is
slow, but a thousand selected people is a slow question, and a limit would be
complexity bought with a guess rather than with a measurement.

## Mention filtering and performance

`Redmine::Acts::Mentionable` scans the text on save, notifies the users it finds and
throws the result away. There is no mentions table on any Redmine from 5.0 to 7.0, so
the filter reads `issues.description` and `journals.notes` directly. That has two
consequences worth knowing before you enable it.

**Accuracy.** Matching happens in two stages. A cheap `LIKE '%@%'` throws away every
text that holds no `@` at all, then one regular expression carries all the selected
logins and applies the word boundary that `LIKE` cannot express. `@jan` therefore does
not match `@jansen`, nor an address like `someone@jan.example`, and a dot or an
underscore in a login stays a literal. Case is ignored, as it is by Redmine: `@JSmith`
finds the login `jsmith`.

The filter is measured against Redmine's own `MENTION_PATTERN` — the pattern that
decided whether you got the notification — over a corpus of forty texts. They agree
on everything except three, which the specs pin so the list can only shrink:

| text | Redmine notifies | the filter matches | why |
|---|---|---|---|
| `@jan é` written as `@jané` | no | yes | the boundary is "a character no login may contain", so a letter from another script ends the mention; Redmine wants punctuation, a space or the end of the text |
| `@jan_` | yes | no | Redmine counts `_` as punctuation, but `_` is legal in a login, so the text reads as the login `jan_` |
| `@jan.@x` | yes | no | reads as the login `jan.@x` |

Trailing punctuation is handled: `@jan.`, `@jan...`, `@jan,` and `@jan)` are all
mentions of `jan`, while `@jan.example` is a mention of the login `jan.example`.

On SQLite there is no `REGEXP` without a user defined function, so the filter falls
back to one `LIKE '%@login%'` per login and accepts the false positives that brings.
PostgreSQL and MySQL/MariaDB use the expression.

Unlike Redmine's notifications, the filter cannot tell that a mention sits inside a
code block or a quoted reply, since that is not expressible in SQL.

**Cost.** The condition is a correlated `EXISTS`, so it scales with the number of
issues the rest of your query leaves to check, not with the size of the journals
table. Measured on 20 000 issues and 200 000 journals, 133 000 of them carrying notes:

| | unscoped | with a filter leaving ~1000 issues |
|---|---|---|
| PostgreSQL | 290 ms | 85 ms |
| MySQL/MariaDB | 460 ms | 24 ms |

The cost does not grow with the number of principals selected: one regular expression
carries all of them, so twenty one principals cost the same as one.

So combine it with a project, status or date filter and it stays comfortable. An
unscoped *"everything mentioning me"* over a much larger instance will be slow, and no
amount of tuning in the plugin changes that: a leading wildcard `LIKE` cannot use a
btree index. If you need it unscoped and fast on PostgreSQL, a `pg_trgm` GIN index on
`journals.notes` and `issues.description` makes the `LIKE` indexable. MySQL has no
equivalent for a leading wildcard, so there the answer is to keep the query scoped.

`involved` deliberately does not include mentions, so that it stays a cheap indexed
lookup. Use `involved_or_mentioned` when you want both and accept the text search.

## Install
Follow the commands below for a smooth installation:
* Navigate to your plugins directory:
    * `$ cd $RAILS_ROOT/plugins`
* Clone the repository:
    * `$ git clone https://github.com/jcatrysse/redmine_parent_child_filters.git`

The plugin ships no migration, so `redmine:plugins:migrate` is not required.

Don't forget to restart your Redmine afterward!

## Uninstall
* Simply remove the plugin folder.
* Restart Redmine for the changes to take effect.

There is nothing else to undo: the plugin ships no migration, adds no column, no
index and no table, and stores nothing outside its own row in `settings`. Removing
the folder and restarting is a complete rollback, at any version, with no downtime
beyond the restart.

Saved queries that used a filter from this plugin keep their stored filter, which
Redmine then ignores as unknown. Re-installing the plugin brings them back.

## Upgrading from a version before 1.0.0

Two filter behaviours changed meaning, so a saved query can return different rows
than it used to. Both are listed in full in the [changelog](CHANGELOG.md); in short:

* **`child_tracker` with "is not"** now means "has no child with that tracker",
  matching every other "is not" in Redmine, rather than "has a child with a
  different tracker". To get the old rows, use **is** and select the other trackers.
* **"any" and "none"** now mean "such a relative exists" and "it does not". They
  previously returned either every issue or none, so any saved query using them was
  not answering a question anyway.

To find the saved queries that need looking at:

```ruby
# Rails console, read only
fields = %w[child_tracker_id child_status_id a_child_tracker_id a_child_status_id
            parent_tracker_id parent_status_id a_parent_tracker_id a_parent_status_id
            root_tracker_id root_status_id tree_tracker_id tree_status_id
            tree_parent_tracker_id tree_parent_status_id
            tree_child_tracker_id tree_child_status_id]

Query.where.not(:filters => nil).find_each do |query|
  affected = (query.filters || {}).select do |field, options|
    fields.include?(field) && ['!', '*', '!*'].include?(options[:operator])
  end
  next if affected.empty?

  puts "##{query.id} #{query.name.inspect} (#{query.user&.login || 'anonymous'}): " \
       "#{affected.keys.join(', ')}"
end
```

Nothing else about the upgrade needs attention: no migration to run, and the plugin
refuses to overwrite a filter Redmine or another plugin already provides.

## Development

The specs boot a real Redmine and run every filter against a real database, so they
need a Redmine checkout with the plugin installed in `plugins/`. Three scripts do
that, and CI runs the same three, so a green laptop and a green pipeline mean the
same thing:

```bash
./.codex/redmine_clone.sh 6.1-stable   # clone Redmine, copy the plugin into plugins/
./.codex/test_setup.sh                 # pick a Ruby, install the gems, migrate
./.codex/test_plugin.sh                # run the suite

./.codex/test_plugin.sh spec/mention_filter_spec.rb -e 'word boundaries'
```

A fourth script measures rather than tests:

```bash
./.codex/benchmark.sh                            # 20 000 issues, 100 000 journals
PCF_BENCH_ISSUES=100000 ./.codex/benchmark.sh    # bigger
PCF_BENCH_NO_VISIBILITY=1 ./.codex/benchmark.sh  # price of the visibility scoping
```

It seeds whatever it needs into the test database and leaves the rows behind, so a
second run reuses the dataset. Drop the database to start over.

`redmine_clone.sh` takes any Redmine branch (`5.0-stable` … `7.0-stable`, `master`).
`test_setup.sh` reads the Ruby range out of that checkout's Gemfile and uses
[mise](https://mise.jdx.dev/) to fetch a matching Ruby when it is installed,
locally and never globally; otherwise it uses the Ruby on `PATH` and says so. It
provisions a local database server unless you point it at one:

| variable | default | meaning |
|---|---|---|
| `PCF_DB` | `postgresql` | `postgresql`, `mysql` or `mariadb` — and it means it: `mysql` installs `mysql-server`, not Ubuntu's `default-mysql-server`, which is MariaDB. The script prints the server version and warns if the two disagree |
| `PCF_DB_NAME` / `_USER` / `_PASSWORD` / `_HOST` / `_PORT` | `redmine_test`, `redmine`, `redmine`, `127.0.0.1`, per adapter | connection details |
| `PCF_PROVISION_DB` | `1`, or `0` in CI | install and start a server with `sudo` |
| `REDMINE_DIR` | `redmine` | where the checkout lives |
| `PCF_RUBY` | derived from the Gemfile | pin the Ruby version |

Core fixtures are loaded once and each example runs in a rolled back transaction,
so the database is left untouched.

The suite covers every filter against a real database: each filter with each of
its operators, the hierarchy and involvement semantics, the negations and the NULL
cases, SQL injection through filter values, translation completeness, the
administration switches, and the paths a filter travels in production, being the
issue list, the Gantt, the calendar, CSV, PDF, Atom, the REST API and a stored
query. One spec runs every filter and operator as a non member and asserts that no
issue from a project they cannot see is ever returned.

CI runs the whole suite on Redmine 5.0, 5.1, 6.0, 6.1 and 7.0, against PostgreSQL,
MySQL and MariaDB, on every push and pull request, and weekly against Redmine trunk
where it is allowed to fail. A separate lint workflow runs RuboCop, ShellCheck and a
parse of every locale file.

Style follows Redmine's own `.rubocop.yml`, so plugin code reads like the core code
it patches:

```bash
gem install rubocop -v 1.88.2 && rubocop
shellcheck --external-sources .codex/*.sh
```

## License
Distributed under the MIT License. Enjoy the flexibility and freedom it brings!
