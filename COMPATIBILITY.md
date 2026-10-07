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
| `Query#validate_query_filters`, `#add_filter_error(field, message)` | the validation of the filter values, with Redmine's own "is invalid" | the plugin's check of the dates given to `is not` stops running, and a value that is no date reaches SQL again |
| core's `assigned_to_id` and `description` issue filters | offered on every issue query; a plugin that hides the field removes the filter | the people filters stop using the assignee and the description |
| `Query#sql_for_field(field, operator, value, db_table, db_field)` | five positional arguments; builds the journal lookup for `ev` / `!ev` / `cf` | the status history operators break — the plugin feature-detects the operators but not the signature, so this is asserted |
| `Issue.visible_condition(user)` | a SQL string mentioning only the `issues` and `projects` tables | **the visibility scoping of every relative subquery**, see below |
| `Journal.visible_notes_condition(user, skip_pre_condition:)` | a SQL string mentioning only `journals` and `projects` | private notes could become visible through the mention filter; the original project filter rewrites `journals` to an alias and would read moves from journals the user may not see |
| `Issue#journalized_attribute_names` | includes `project_id`, so every move writes a `journal_details` row with the old and new project | both project filters would see no moves at all |
| `Issue#after_project_change` | private; moves subtasks along with their parent through `child.send(:project=, project, true)` and `child.save`, *without* a journal | the plugin wraps it to scope the subtask journaling. If it stops calling `project=`, subtasks are moved unjournaled again, as in plain Redmine. If Redmine starts journaling these moves itself, the patch does nothing, because the subtask already carries a journal |
| `Issue#project=(project, keep_tracker = false)` | the setter every project change goes through, and the one after_project_change calls on each subtask | the plugin calls `init_journal` here, before the change, so that the journal sees the attributes as they were |
| `Issue#init_journal`, `#current_journal`, `Journal#notify=` | a journal snapshots the attributes when it is created, is saved by `create_journal` after save, and sends no mail when `notify` is false | the subtask journal would record nothing, or mail every watcher of every subtask |
| `Setting.plugin_<id>` | the stored hash as saved, *without* the plugin defaults merged in | nothing breaks; the fallback to the default for an absent key becomes redundant |
| `Query#project_values` | the project list of core's project filter, with `mine` and `bookmarks` | the project filters' value list |
| core's `project_id` issue filter | type `:list`, so no history operators | `project_history_id` becomes a duplicate of core and should be retired |
| `Issue.sanitize_sql(array)` | public since Rails 5.2, binds `?` placeholders | the mention `LIKE` patterns |
| `Issue.sanitize_sql_like(string)` | escapes `%` and `_` | a login containing `_` would match as a wildcard |
| `Redmine::Database.like/postgresql?/mysql?/sqlite?` | adapter dispatch | the plugin would emit PostgreSQL syntax everywhere |
| `Redmine::DefaultData::Loader` | only in the benchmark harness | the benchmark, not the plugin |

## Assumptions that are not public API

Three, all deliberate; the first two asserted by the contract spec, the third by the e2e scenario `status-none.mjs`.

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

### Wrapping `buildFilterRow` in the filter form

The status filters that offer "none" have a filter type of their own,
`:pcf_list_status` (Redmine's `:list_status` plus `!*`). Redmine's filter form draws a
row with `buildFilterRow(field, operator, values)` from `application-legacy.js`, which
takes the operators from the global `operatorByType[type]` and draws a value list only
for the types it knows. `assets/javascripts/pcf_filters.js`, loaded through the
`view_layouts_base_html_head` hook, wraps that function: for a filter of the plugin's
type it presents the filter as `list_status` with the longer operator list for the
duration of the call, then restores both. It assumes the globals `buildFilterRow`,
`operatorByType` and `availableFilters` and that `list_status` gets a value list. If
they change, the row of those six filters loses its values or its "none"; nothing else
is affected, and the filters keep working through the URL and the API.

## What the plugin writes

One thing: a journal entry on a subtask that Redmine moves along with its parent,
see `lib/redmine_parent_child_filters/patches/subtask_move_journal_patch.rb`. It is
the same kind of entry a move from the issue form writes, it can be switched off,
and it is asserted against Redmine's behaviour in `spec/core_contract_spec.rb`.

## What the plugin deliberately does not touch

* `Query#statement`, so the AND between filters is untouched and no saved query
  changes meaning.
* the database schema: no migration, no index, no column.
* `ActionView::Base` and `IssuesController`, which core already exposes
  `QueriesHelper` to.
* the shared `operators_by_filter_type` arrays, which are replaced rather than
  mutated so another plugin holding a reference is unaffected.
