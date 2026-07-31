# frozen_string_literal: true

# Measures the filters against a dataset big enough for the planner to behave
# like it does in production, and writes the query plans out so a change can be
# compared rather than guessed at.
#
# Run it through .codex/benchmark.sh rather than directly.
#
# Nothing here asserts a timing. Numbers from a laptop or a shared CI runner are
# not comparable between runs on different machines; what is comparable is the
# shape of the plan and the ratio between two runs on the same machine.

require 'benchmark'

ISSUES      = Integer(ENV.fetch('PCF_BENCH_ISSUES', 20_000))
JOURNALS    = Integer(ENV.fetch('PCF_BENCH_JOURNALS', 100_000))
CHAIN       = 4                       # issues per tree, so trees are CHAIN deep
OUT         = ENV.fetch('PCF_BENCH_OUT', 'tmp/benchmark')
NO_VISIBILITY = ENV['PCF_BENCH_NO_VISIBILITY'] == '1'

# A/B switch for the cost of scoping the relative subqueries. Not a supported
# mode: it exists so the price of the visibility join can be stated as a number
# instead of an opinion.
if NO_VISIBILITY
  module RedmineParentChildFilters
    module Patches
      module IssueQueryPatch
        module InstanceMethods
          def pcf_visible_condition(_table)
            '(1=1)'
          end

          def pcf_visible_join(_table)
            ''
          end
        end
      end
    end
  end
  warn 'WARNING: visibility scoping disabled; measuring the cost of M1 only.'
end

def heading(text)
  puts "\n#{text}"
  puts '-' * text.length
end

# --- seed -------------------------------------------------------------------
# A migrated database holds an admin user and nothing else, so the harness makes
# whatever it needs. Projects differ in visibility on purpose: the relative
# subqueries are scoped by it, so a dataset where every project is public would
# measure the easy case.
def seed!
  Redmine::DefaultData::Loader.load('en') if Redmine::DefaultData::Loader.no_data?

  return if Project.active.count >= 4

  4.times do |i|
    identifier = "pcf-bench-#{i}"
    next if Project.where(:identifier => identifier).exists?

    project = Project.new(:name => "PCF bench #{i}", :identifier => identifier,
                          :is_public => !i.zero?)
    project.trackers = Tracker.all
    project.save!
    project.enabled_module_names = ['issue_tracking']
  end
  puts "seeded #{Project.active.count} projects, #{Tracker.count} trackers, " \
       "#{IssueStatus.count} statuses"
end

# --- dataset ----------------------------------------------------------------
# A dataset that is wrong in a way nobody notices is worse than no dataset: it
# produces numbers, and the numbers get written into a readme.
#
# This runs on every invocation, not only after building, because the rows are left
# behind for the next run to reuse. The first version checked only what it had just
# built — so a database still holding the 20 000 rows the *old* builder wrote, with
# every child its own tree root, would be reused unvalidated and would quietly
# produce the same wrong figures the check exists to prevent.
#
# It aborts rather than repairing. Repairing in place would have to guess which rows
# belong to which tree from ids that may no longer be contiguous, and a benchmark is
# not the place to be clever about someone else's data.
def validate_dataset!
  scope = Issue.where("subject LIKE 'pcf bench %'")
  return if scope.count.zero?

  quoted = Issue.table_name
  mismatched = Issue.connection.select_value(<<~SQL.squish).to_i
    SELECT COUNT(*) FROM #{quoted} c INNER JOIN #{quoted} p ON c.parent_id = p.id
    WHERE c.root_id <> p.root_id
  SQL
  orphaned = scope.where(:root_id => nil).count
  roots = scope.where(:parent_id => nil).count
  expected_roots = scope.count / CHAIN

  return if mismatched.zero? && orphaned.zero? && roots == expected_roots

  abort <<~MSG
    The benchmark dataset is not a tree:
      #{mismatched} children disagree with their parent's root_id
      #{orphaned} issues have no root_id
      #{roots} roots for #{expected_roots} expected trees

    Datasets built before the root_id fix look like this on MySQL and MariaDB, where
    `/` is floating point division. Timing them measures nothing. Drop the rows and
    let this script rebuild them:

      Issue.where("subject LIKE 'pcf bench %'").delete_all

    or drop the whole test database, which is faster.
  MSG
end

# awesome_nested_set rewrites lft and rgt on every insert, which is O(n) per
# issue and so hours for a dataset this size. The rows go in with insert_all and
# the tree bookkeeping is then computed arithmetically: ids from one bulk insert
# are contiguous, so tree t occupies [first + t * CHAIN, first + t * CHAIN + 3].
def build_dataset
  trees = ISSUES / CHAIN
  author = User.where(:admin => true).first || User.first
  priority = IssuePriority.active.first
  projects = Project.active.to_a
  trackers = Tracker.all.to_a
  statuses = IssueStatus.sorted.to_a
  now = Time.current

  puts "building #{trees * CHAIN} issues in #{trees} trees of #{CHAIN}, " \
       "over #{projects.size} projects..."

  rows = (trees * CHAIN).times.map do |i|
    {
      :project_id => projects[i % projects.size].id,
      :tracker_id => trackers[i % trackers.size].id,
      :status_id => statuses[i % statuses.size].id,
      :priority_id => priority.id,
      :author_id => author.id,
      :subject => "pcf bench #{i}",
      :description => (i % 7).zero? ? "cc @#{author.login} please look" : 'nothing to see',
      :created_on => now,
      :updated_on => now,
      :is_private => (i % 23).zero?,
      :done_ratio => 0,
      :lock_version => 0,
      :lft => 1,
      :rgt => 2
    }
  end

  rows.each_slice(2_000) { |slice| Issue.insert_all(slice) }

  scope = Issue.where("subject LIKE 'pcf bench %'")
  first_id = scope.minimum(:id)
  last_id = scope.maximum(:id)
  unless last_id - first_id + 1 == scope.count
    abort 'ids are not contiguous; run this on a database with no concurrent writers'
  end

  # One statement for the whole nested set. offset = position within the tree.
  #
  # root_id is written with modulo rather than integer division on purpose. `/` is
  # integer division on PostgreSQL and floating point division on MySQL and MariaDB,
  # so ((id - first) / CHAIN) * CHAIN rounded to the row itself there instead of to
  # its tree: every child got its own root_id. The dataset looked fine — 20 000
  # issues, 15 000 with a parent — and the tree filters, which key on root_id,
  # quietly measured almost nothing on those two engines. Only integer arithmetic
  # both engines agree on goes in here now.
  quoted = Issue.table_name
  Issue.connection.execute(<<~SQL.squish)
    UPDATE #{quoted} SET
      root_id   = #{first_id} + ((id - #{first_id}) - ((id - #{first_id}) % #{CHAIN})),
      lft       = ((id - #{first_id}) % #{CHAIN}) + 1,
      rgt       = (#{CHAIN} * 2) - ((id - #{first_id}) % #{CHAIN}),
      parent_id = CASE WHEN (id - #{first_id}) % #{CHAIN} = 0 THEN NULL ELSE id - 1 END
    WHERE id BETWEEN #{first_id} AND #{last_id}
  SQL

  validate_dataset!

  puts "building #{JOURNALS} journals..."
  issue_ids = scope.pluck(:id)
  notes = JOURNALS.times.map do |i|
    {
      :journalized_id => issue_ids[i % issue_ids.size],
      :journalized_type => 'Issue',
      :user_id => author.id,
      :notes => (i % 3).zero? ? "ping @#{author.login} about this" : "just a note #{i}",
      :private_notes => (i % 11).zero?,
      :created_on => now,
      :updated_on => now
    }
  end
  notes.each_slice(5_000) { |slice| Journal.insert_all(slice) }

  analyze!
  puts "issues: #{Issue.count}, journals: #{Journal.count}"
end

def analyze!
  case ActiveRecord::Base.connection.adapter_name
  when /postg/i then Issue.connection.execute('ANALYZE issues; ANALYZE journals; ANALYZE projects')
  else Issue.connection.execute('ANALYZE TABLE issues, journals, projects')
  end
end

# --- the queries ------------------------------------------------------------
def query_for(filters)
  query = IssueQuery.new(:name => '_')
  query.filters = {}
  filters.each { |field, (operator, values)| query.add_filter(field, operator, values) }
  query
end

def cases
  closed = IssueStatus.where(:is_closed => true).first || IssueStatus.sorted.last
  tracker = Tracker.first
  me = User.where(:admin => true).first || User.first

  [
    ['child_status_id',              {'child_status_id' => ['=', [closed.id.to_s]]}],
    ['child_status_id !',            {'child_status_id' => ['!', [closed.id.to_s]]}],
    ['a_child_status_id',            {'a_child_status_id' => ['=', [closed.id.to_s]]}],
    ['a_parent_tracker_id',          {'a_parent_tracker_id' => ['=', [tracker.id.to_s]]}],
    ['a_specific_parent_tracker_id', {'a_specific_parent_tracker_id' => ['=', ["#{tracker.id}:3"]]}],
    ['root_tracker_id',              {'root_tracker_id' => ['=', [tracker.id.to_s]]}],
    ['tree_status_id',               {'tree_status_id' => ['=', [closed.id.to_s]]}],
    # The structural filters. They carry the most tables per subquery, because
    # "has a visible relative" needs an alias and a project join on each side, so
    # they are the ones to watch when the scoping changes.
    ['tree_has_parent_or_child',     {'tree_has_parent_or_child' => ['=', ['1']]}],
    ['tree_parent_tracker_id',       {'tree_parent_tracker_id' => ['=', [tracker.id.to_s]]}],
    ['tree_child_tracker_id',        {'tree_child_tracker_id' => ['=', [tracker.id.to_s]]}],
    ['involved_id',                  {'involved_id' => ['=', [me.id.to_s]]}],
    ['mentioned_id',                 {'mentioned_id' => ['=', [me.id.to_s]]}]
  ]
end

# The Rails query cache is on inside `rails runner`, which makes a second
# measurement of the same statement free and the whole benchmark a lie.
#
# The median of several runs, not one run. A single measurement of the heavier tree
# filters varied by 50% between runs of identical code on this machine, which is
# more than the differences a reader would want to draw a conclusion from — and it
# did lead to two wrong conclusions before this was changed.
REPEATS = Integer(ENV.fetch('PCF_BENCH_REPEATS', 5))

def timed(query)
  ActiveRecord::Base.uncached do
    query.issue_count # warm the plan
    times = Array.new(REPEATS) { Benchmark.realtime { query.issue_count } * 1000 }
    times.sort[times.size / 2]
  end
end

def explain(query)
  sql = query.issues.to_sql
  verb = ActiveRecord::Base.connection.adapter_name.match?(/postg/i) ? 'EXPLAIN ANALYZE' : 'EXPLAIN'
  rows = Issue.connection.select_all("#{verb} #{sql}").rows
  rows.map { |row| row.join(' | ') }.join("\n")
rescue StandardError => e
  "EXPLAIN failed: #{e.class}: #{e.message}"
end

# --- report -----------------------------------------------------------------
def index_report
  wanted = {
    'issues' => [%w[parent_id], %w[root_id lft rgt], %w[tracker_id], %w[status_id], %w[project_id]],
    'journals' => [%w[journalized_id journalized_type]]
  }

  heading 'Indexes the filters rely on'
  wanted.each do |table, columns_list|
    have = Issue.connection.indexes(table).map(&:columns)
    have << ['id'] # the primary key is not listed as an index
    columns_list.each do |columns|
      hit = have.any? { |existing| existing.first(columns.size) == columns }
      puts "  #{table}(#{columns.join(', ')}): #{hit ? 'present' : 'MISSING'}"
    end
  end
  puts '  projects(id): present (primary key, used by the visibility join)'
  puts "\n  All of these ship with Redmine. The plugin needs no index of its own."
end

# --- mention filter at scale ------------------------------------------------
# The mention filter folds every selected login into one regular expression, which
# is what keeps a large selection from becoming a hundred SQL predicates. It also
# means the statement, and the pattern the engine has to compile, grow with the
# selection. Whether that matters is a question for a measurement, not for a guess,
# and the answer decides whether a cap on the selection is worth its complexity.
#
#   PCF_BENCH_PRINCIPALS=1 ./.codex/benchmark.sh
def mention_scale!(sizes)
  wanted = sizes.max
  have = User.where("login LIKE 'pcf-bench-user-%'").count

  if have < wanted
    puts "  creating #{wanted - have} users..."
    (have...wanted).each do |i|
      user = User.new(:login => "pcf-bench-user-#{i}", :firstname => 'Bench', :lastname => "User#{i}",
                      :mail => "pcf-bench-user-#{i}@example.net")
      user.password = 'pcf-bench-secret-1'
      user.save!(:validate => false)
    end
  end

  ids = User.where("login LIKE 'pcf-bench-user-%'").order(:id).limit(wanted).pluck(:id)

  puts format('  %10s %12s %14s %12s', 'principals', 'time', 'statement', 'longest login')
  sizes.each do |size|
    query = query_for('mentioned_id' => ['=', ids.first(size).map(&:to_s)])
    statement = query.statement
    longest = User.where(:id => ids.first(size)).maximum('LENGTH(login)')

    puts format('  %10d %9.1f ms %11d B %12d', size, timed(query), statement.bytesize, longest)
  end
end

# What the dataset actually contains, printed next to the timings.
#
# Benchmark output gets copied into issues and readmes without the database that
# produced it. The run that measured nothing on MySQL reported "20 000 issues,
# 100 000 journals" and looked entirely healthy; it would have been obvious at a
# glance next to "5 000 roots, 15 000 links, 0 visible links".
def dataset_report
  scope = Issue.where("subject LIKE 'pcf bench %'")
  quoted = Issue.table_name
  links = Issue.connection.select_value(<<~SQL.squish).to_i
    SELECT COUNT(*) FROM #{quoted} c INNER JOIN #{quoted} p ON c.parent_id = p.id
  SQL
  visible_links = Issue.connection.select_value(<<~SQL.squish).to_i
    SELECT COUNT(*) FROM #{quoted} c
    INNER JOIN #{quoted} p ON c.parent_id = p.id
    WHERE c.root_id = p.root_id
  SQL

  heading 'The dataset these timings come from'
  puts format('  %-22s %d', 'benchmark issues', scope.count)
  puts format('  %-22s %d', 'tree roots', scope.where(:parent_id => nil).count)
  puts format('  %-22s %d', 'parent/child links', links)
  puts format('  %-22s %d', 'links inside one tree', visible_links)
  puts format('  %-22s %d', 'private issues', Issue.where(:is_private => true).count)
  puts format('  %-22s %d', 'projects', Project.count)
  puts format('  %-22s %d', 'non public projects', Project.where(:is_public => false).count)
  puts format('  %-22s %d', 'journals', Journal.count)
end

def main
  seed!
  User.current = User.where(:admin => true).first || User.first
  abort 'no user to run as; migrate the database first' unless User.current
  build_dataset if Issue.where("subject LIKE 'pcf bench %'").count < ISSUES

  # Always, whether the rows were just built or left over from an earlier run.
  validate_dataset!

  analyze!
  FileUtils.mkdir_p(OUT)
  adapter = ActiveRecord::Base.connection.adapter_name

  dataset_report
  heading "Timings on #{adapter}, #{Issue.count} issues, #{Journal.count} journals"
  puts format('  %-30s %12s %12s', 'filter', 'unscoped', 'scoped')
  plans = []

  cases.each do |name, filters|
    unscoped = query_for(filters)
    scoped = query_for(filters.merge('project_id' => ['=', [Project.first.id.to_s]]))

    puts format('  %-30s %9.1f ms %9.1f ms', name, timed(unscoped), timed(scoped))
    plans << "== #{name} (unscoped) ==\n#{explain(unscoped)}\n"
  end

  if ENV['PCF_BENCH_PRINCIPALS'] == '1'
    heading 'The mention filter as the selection grows'
    mention_scale!([1, 100, 500, 1000])
  end

  suffix = NO_VISIBILITY ? '-no-visibility' : ''
  path = File.join(OUT, "plans-#{adapter.downcase}#{suffix}.txt")
  File.write(path, plans.join("\n"))
  puts "\n  query plans written to #{path}"

  index_report
end

main
