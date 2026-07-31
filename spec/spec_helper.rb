# frozen_string_literal: true

# Boots a real Redmine so that the filters are exercised against a real
# database. String level assertions cannot catch invalid SQL, NULL semantics or
# differences between PostgreSQL and MySQL, which is exactly what these filters
# are made of.
#
# Run from the Redmine root:
#   RAILS_ENV=test bundle exec rspec plugins/redmine_parent_child_filters/spec

ENV['RAILS_ENV'] ||= 'test'

REDMINE_ROOT = File.expand_path('../../..', __dir__)
require File.join(REDMINE_ROOT, 'config', 'environment')

require 'rspec'
# Not autoloaded on Rails 6.1 (Redmine 5.x), which only pulls it in from its own
# test helper.
require 'active_record/fixtures'

FIXTURES_PATH = File.join(REDMINE_ROOT, 'test', 'fixtures')
FIXTURE_NAMES = Dir[File.join(FIXTURES_PATH, '*.yml')].map { |f| File.basename(f, '.yml') }.sort.freeze

module PcfSpecHelpers
  # Builds an issue, optionally below a parent, with the minimum required
  # attributes. Nested set bookkeeping (lft/rgt/root_id) is left to Redmine.
  def create_issue(project: Project.find(1), tracker: nil, status: nil, parent: nil, author: User.find(1))
    issue = Issue.new(
      :project => project,
      :tracker => tracker || project.trackers.first,
      :status => status || IssueStatus.sorted.first,
      :author => author,
      :subject => "pcf test issue",
      :priority => IssuePriority.active.first
    )
    issue.parent_issue_id = parent.id if parent
    issue.save!
    issue.reload
  end

  # A fresh IssueQuery carries a default "status is open" filter. Tests assert on
  # the plugin filters alone, so it is dropped.
  def unfiltered_query
    query = IssueQuery.new(:name => '_')
    query.filters = {}
    query
  end

  # Runs a query end to end and returns the matching issue ids. Any invalid SQL
  # surfaces here as Query::StatementInvalid.
  def issue_ids_for(filters)
    query = unfiltered_query
    filters.each { |field, (operator, values)| query.add_filter(field, operator, values) }
    raise "invalid query: #{query.errors.full_messages.join(', ')}" unless query.valid?

    query.issues.map(&:id).sort
  end

  # Redmine 5.0 has no "has been" / "has never been" / "changed from" operators.
  def history_operators?
    Query.operators_by_filter_type[:list_status].include?('ev')
  end

  # Counts the self joins on the issues table, which is what the depth limit
  # bounds. Visibility scoping adds one join on projects per alias; those are
  # bounded by the same number and are not what these assertions are about.
  def pcf_issue_joins(statement)
    statement.scan(/INNER JOIN #{Issue.table_name}\b/).size
  end

  def all_visible_issue_ids
    unfiltered_query.issues.map(&:id).sort
  end

  # True when the server behind the mysql2 adapter is MariaDB. Redmine's
  # Redmine::Database.mysql? answers for both, and here they differ.
  def pcf_mariadb?
    ActiveRecord::Base.connection.select_value('SELECT VERSION()').to_s.match?(/mariadb/i)
  end

  # Bounds a query at the database instead of in Ruby.
  #
  # Ruby's Timeout cannot interrupt a query blocking inside the database driver:
  # Thread#raise only lands at a safepoint, so the exception is delivered once the
  # call returns. Measured on MySQL 8, Timeout.timeout(3) around a 30 second query
  # returned after 30.0 seconds — it reports the overrun afterwards but bounds
  # nothing, and a planner blow-up still burns the whole job. Every engine Redmine
  # supports enforces a deadline itself; the same query came back in 3.0 seconds
  # once the server owned it.
  #
  # An overrun surfaces as a descendant of ActiveRecord::StatementInvalid (Redmine
  # wraps it as Query::StatementInvalid), which is what the caller asserts on.
  def pcf_with_statement_timeout(seconds)
    conn = ActiveRecord::Base.connection
    setting, value =
      if Redmine::Database.postgresql?
        ['statement_timeout', "#{(seconds * 1000).to_i}ms"]
      elsif Redmine::Database.mysql?
        # MariaDB named it differently and counts seconds; MySQL counts
        # milliseconds. Neither accepts the other's variable.
        pcf_mariadb? ? ['max_statement_time', seconds] : ['max_execution_time', (seconds * 1000).to_i]
      end

    # An engine we cannot bound (SQLite): the caller still measures and asserts,
    # it just does not fail fast.
    return yield if setting.nil?

    previous = conn.select_value(
      Redmine::Database.postgresql? ? "SHOW #{setting}" : "SELECT @@SESSION.#{setting}"
    )
    conn.execute("SET SESSION #{setting} = #{conn.quote(value)}")
    begin
      yield
    ensure
      # When the deadline does fire on PostgreSQL the surrounding transaction is left
      # aborted, so restoring here fails too. That is the failure path; letting its
      # secondary error escape would bury the message the caller wants to show.
      begin
        conn.execute("SET SESSION #{setting} = #{conn.quote(previous)}")
      rescue ActiveRecord::StatementInvalid
        nil
      end
    end
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include PcfSpecHelpers

  config.before(:suite) do
    ActiveRecord::FixtureSet.create_fixtures(FIXTURES_PATH, FIXTURE_NAMES)
  end

  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end

  config.before(:each) do
    User.current = User.find(1) # admin, sees every project
    I18n.locale = :en
    Setting.clear_cache
  end

  config.after(:each) do
    User.current = nil
  end
end
