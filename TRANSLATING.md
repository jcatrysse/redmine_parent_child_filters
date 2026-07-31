# Translating this plugin

The plugin ships all 50 languages Redmine does. This explains how the strings are
built, because they are not written the way plugin strings usually are, and a
contributor who does not know that will make them worse.

## The labels are composed, not authored

A filter label is `"<relation><separator><attribute>"`, where the relation and the
attribute come from **Redmine's own translation** in that language:

| key used | English | German | Japanese | Dutch |
|---|---|---|---|---|
| `label_subtask_plural` | Subtasks | Untergeordnete Tickets | 子チケット | Subtaken |
| `field_status` | Status | Status | ステータス | Status |
| result | `Subtasks: Status` | `Untergeordnete Tickets: Status` | `子チケット：ステータス` | `Subtaken: Status` |

This is deliberate, and it is why the filter reads with the words that language
already uses everywhere else in Redmine. A user who sees "Untergeordnete Tickets"
in the issue form sees the same words in the filter dropdown.

CJK locales use a full width colon (`：`) with no following space, because that is
the convention in those scripts and it is what Redmine's own strings do.

### Why some locales contain English words

Croatian shows `Parent task: Status`. That is not an untranslated string — it is
Redmine's own `hr.yml`:

```yaml
hr:
  field_parent_issue: "Parent task"
  label_subtask_plural: "Subtasks"
  field_tracker: "Tracker"
```

"Translating" those would make the filter name disagree with the field name shown
two lines higher in the same interface. **Do not fix them here.** If they should be
Croatian, they should be Croatian in Redmine, and the fix belongs upstream — where
it will then flow into this plugin for free.

## Adding a key

Every locale file carries the same keys; `spec/locales_spec.rb` fails if one is
missing, and the Lint workflow parses all 50. So a new key means 50 edits.

Before adding one, ask whether it can be composed instead. Two examples of avoiding
new prose:

* the settings page says `1 = Parent task` — a number, an equals sign and Redmine's
  own `field_parent_issue`. Grammatical in every language, nothing to translate.
* the effective depth range is rendered as `1–5`. Numbers need no translation.

If a key genuinely needs a sentence, say so in the pull request and mark the
languages you cannot vouch for. A machine translation that reads as a native
sentence but says the wrong thing is worse than an English fallback, because nobody
will ever notice it.

## Two traps

**`no:` is not a string.** Psych — the YAML parser Ruby and therefore Redmine uses
— reads a bare `no` as the boolean `false`. Norwegian is the locale this bites. Every
locale key in this plugin is quoted for that reason:

```yaml
"no":
  label_filter_root_id: "Root"
```

The Lint workflow parses every file and checks that the top level key equals the
filename, which is what catches it.

**Values are quoted too.** A value beginning with `@`, `%`, `*`, `&` or `-`, or
containing a `:` followed by a space, changes meaning unquoted. Quoting everything
is cheaper than remembering which.

## Checking your work

```bash
./.codex/redmine_clone.sh 6.1-stable
./.codex/test_setup.sh
./.codex/test_plugin.sh spec/locales_spec.rb
```

That asserts every file parses, carries every key, resolves through Rails I18n and
leaves no `translation missing` in the rendered settings page.
