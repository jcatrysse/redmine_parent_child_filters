# What this plugin assumes about Redmine

A plugin that adds filters cannot avoid leaning on the internals of `Query`. This
file lists every place where it does, what the assumption is, and what breaks if
Redmine changes it. `spec/core_contract_spec.rb` asserts each one, so an upgrade
that moves any of them fails a named example instead of producing wrong SQL.

Verified against Redmine 5.0, 5.1, 6.0, 6.1 and 7.0.

## Public API, used as documented

These are ordinary public methods. They are listed because the plugin depends on
their *return shape*, not only on their existence.

| What | Assumed | Breaks if |
|---|---|---|
| `Query#add_available_filter(field, options)` | registers a filter and returns the collection | the options keys `:type`, `:values`, `:label` change meaning |
| `Query#available_filters` | `{field => QueryFilter}`, insertion ordered | the order stops being insertion order, which would scramble the dropdown |
| `QueryFilter#[]` | `[:values]` resolves a `Proc`, `[:name]` gives the translated label | value lambdas stop being called lazily |
| `Query#delete_available_filter(field)` | removes one filter | — |
| `Query#filters`, `#operator_for(field)` | the current filter set and one operator | a paired tracker/status filter can no longer see its companion |
| `Query.operators_by_filter_type` | a `class_attribute` Hash of type to operator list | the plugin's date `is not` operator disappears |
| `Query#sql_for_field(field, operator, value, db_table, db_field)` | five positional arguments; builds the journal lookup for `ev` / `!ev` / `cf` | the status history operators break — the plugin feature-detects the operators but not the signature, so this is asserted |
| `Issue.visible_condition(user)` | a SQL string mentioning only the `issues` and `projects` tables | **the visibility scoping of every relative subquery**, see below |
| `Journal.visible_notes_condition(user, skip_pre_condition:)` | a SQL string correlated on `journals` | private notes could become visible through the mention filter |
| `Issue.sanitize_sql(array)` | public since Rails 5.2, binds `?` placeholders | the mention `LIKE` patterns |
| `Issue.sanitize_sql_like(string)` | escapes `%` and `_` | a login containing `_` would match as a wildcard |
| `Redmine::Database.like/postgresql?/mysql?/sqlite?` | adapter dispatch | the plugin would emit PostgreSQL syntax everywhere |
| `Redmine::DefaultData::Loader` | only in the benchmark harness | the benchmark, not the plugin |

## Assumptions that are not public API

Two, both deliberate, both asserted.

### Rewriting table names in `Issue.visible_condition`

Every relative subquery has to apply the current user's visibility to a *row
reached through an alias*, and `visible_condition` is written against the literal
`issues` and `projects` tables. The plugin rewrites those two names:

```ruby
Issue.visible_condition(User.current)
     .gsub(/\bissues\b/, 'child')
     .gsub(/\bprojects\b/, 'child_projects')
```

This is the idiom Redmine uses itself — see the `total_estimated_hours` column in
`IssueQuery`, which does `gsub(/\bissues\b/, 'subtasks')` for the same reason.

It is safe because the condition contains no user supplied strings: only numeric
ids, and the module name `issue_tracking`, which neither pattern can match. The
contract spec asserts exactly that — that the condition mentions no table other
than the ones the plugin knows how to alias, and that after rewriting no bare
`issues.` or `projects.` reference is left.

It breaks if a future Redmine references a third table in that condition without
qualifying it through a subquery of its own. The spec then fails and names the
table.

### Swapping `@available_filters` while core builds the dropdown

`filters_options_for_select` is reused as-is so that upstream changes to the
grouping of core's own filters keep working. To keep the plugin's filters out of
core's grouping, they are hidden for the duration of the call:

```ruby
query.instance_variable_set(:@available_filters, available_filters.except(*plugin_filters))
options = super
ensure
query.instance_variable_set(:@available_filters, available_filters)
```

The public alternatives were considered and rejected:

* `delete_available_filter` + re-adding loses the insertion order, so the plugin's
  filters would move to the end of the dropdown and core's own grouping would see
  a different order than it built.
* passing a delegator instead of the query fails because core calls
  `query.is_a?(IssueQuery)`, which a `SimpleDelegator` answers `false`.
* building a second query object cannot be trusted to reproduce the first one's
  available filters, which depend on the project, the user and anything another
  plugin adds.

Mutating and restoring the real object under `ensure` is the smallest assumption
of the three: it needs the ivar to be named `@available_filters` and nothing else.
The spec asserts that `available_filters` reads that ivar, and that the query is
left exactly as it was found.

## What the plugin deliberately does not touch

* `Query#statement`, so the AND between filters is untouched and no saved query
  changes meaning.
* the database schema: no migration, no index, no column.
* `ActionView::Base` and `IssuesController`, which core already exposes
  `QueriesHelper` to.
* the shared `operators_by_filter_type` arrays, which are replaced rather than
  mutated so another plugin holding a reference is unaffected.
