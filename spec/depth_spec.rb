# frozen_string_literal: true

require_relative 'spec_helper'

# The depth based filters turn a selected level into one self join per level. The
# level arrives in the filter value, so it is user input; the bound on it comes
# from a plugin setting, so it is administrator input. Neither may be trusted to
# be sane: the settings form offers 1..10, but a hand written POST or a console
# assignment can store anything, and a hand written filter url can ask for any
# level the bound allows.
RSpec.describe 'depth bounds' do
  PCF_DEPTH_SETTINGS = [
    ['missing',        {}],
    ['empty',          {'min_depth' => '', 'max_depth' => ''}],
    ['non numeric',    {'min_depth' => 'abc', 'max_depth' => 'xyz'}],
    ['negative',       {'min_depth' => '-5', 'max_depth' => '-1'}],
    ['zero',           {'min_depth' => '0', 'max_depth' => '0'}],
    ['reversed',       {'min_depth' => '8', 'max_depth' => '3'}],
    ['above the cap',  {'min_depth' => '1', 'max_depth' => '11'}],
    ['absurd',         {'min_depth' => '1', 'max_depth' => '10000'}],
    ['float',          {'min_depth' => '1.9', 'max_depth' => '4.9'}],
    ['nil',            {'min_depth' => nil, 'max_depth' => nil}]
  ].freeze

  def with_settings(overrides)
    previous = Setting.plugin_redmine_parent_child_filters
    Setting.plugin_redmine_parent_child_filters = previous.merge(overrides)
    yield
  ensure
    Setting.plugin_redmine_parent_child_filters = previous
  end

  let(:cap) { RedmineParentChildFilters::MAX_DEPTH }

  PCF_DEPTH_SETTINGS.each do |name, overrides|
    context "with #{name} depth settings" do
      it 'yields a range inside 1..MAX_DEPTH, ascending' do
        with_settings(overrides) do
          range = RedmineParentChildFilters.depth_range

          expect(range.first).to be >= 1
          expect(range.last).to be <= cap
          expect(range.first).to be <= range.last
        end
      end

      it 'offers no level above the cap in the filter values' do
        with_settings(overrides) do
          values = unfiltered_query.available_filters['a_specific_parent_tracker_id'][:values]
          depths = values.map { |_label, value| value.split(':').last.to_i }.uniq

          expect(depths).not_to be_empty
          expect(depths.max).to be <= cap
          expect(depths.min).to be >= 1
        end
      end

      # The bound is what stops a crafted value from generating joins without
      # end, so it has to hold whatever the setting says.
      it 'never builds more than MAX_DEPTH joins, whatever the value asks for' do
        with_settings(overrides) do
          query = unfiltered_query
          query.add_filter('a_specific_parent_tracker_id', '=', ["#{Tracker.first.id}:9999"])
          statement = query.statement

          expect(pcf_issue_joins(statement)).to be <= cap
        end
      end
    end
  end

  it 'ignores a level above the cap rather than clamping it onto another level' do
    query = unfiltered_query
    query.add_filter('a_specific_parent_tracker_id', '=', ["#{Tracker.first.id}:9999"])

    # Nothing was asked that can be answered, so the filter matches nothing
    # rather than quietly answering about level 1.
    expect(query.statement).to include('1=0')
    expect(query.statement).not_to include('INNER JOIN')
  end

  # Every level costs one self join, and the visibility scoping adds one more table
  # per level. MySQL's optimiser searches join orders exhaustively, so past about a
  # dozen tables the planning cost explodes: measured on these very fixtures, MySQL 8
  # took 12.75s at twelve tables and never returned at fourteen, while PostgreSQL and
  # MariaDB planned all of them in milliseconds.
  #
  # The deadline is the point of this example. Without one a blow-up does not fail,
  # it hangs, and the job dies half an hour later on its own timeout with nothing
  # useful in the log — which is exactly what happened before the join order hint was
  # added. The deadline is set on the server rather than with Timeout because Timeout
  # cannot interrupt a query blocking in the driver; see pcf_with_statement_timeout.
  PCF_DEPTH_DEADLINE = 20

  it 'answers at the deepest level the settings offer, quickly' do
    with_settings('min_depth' => '1', 'max_depth' => RedmineParentChildFilters::MAX_DEPTH.to_s) do
      query = unfiltered_query
      query.add_filter('a_specific_parent_tracker_id', '=',
                       ["#{Tracker.first.id}:#{RedmineParentChildFilters::MAX_DEPTH}"])

      expect(pcf_issue_joins(query.statement)).to eq(RedmineParentChildFilters::MAX_DEPTH)

      elapsed = nil
      error = nil
      pcf_with_statement_timeout(PCF_DEPTH_DEADLINE) do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          query.issue_count
        rescue ActiveRecord::StatementInvalid => e
          error = e
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end

      expect(error).to be_nil,
                       "the deepest level did not finish within #{PCF_DEPTH_DEADLINE}s on " \
                       "#{ActiveRecord::Base.connection.adapter_name}: #{error&.message}"

      # Generous: the fixtures hold a few dozen issues, so anything above a second
      # here is the planner, not the data.
      expect(elapsed).to be < 5,
                         "the deepest level took #{elapsed.round(2)}s on " \
                         "#{ActiveRecord::Base.connection.adapter_name}"
    end
  end

  # The guard above only guards if the deadline is really enforced by the server, and
  # a deadline that silently fails to apply looks exactly like a fast query. So assert
  # the mechanism itself rather than trusting it.
  it 'lets the database enforce the deadline it is given' do
    skip 'no server side deadline on this engine' unless
      Redmine::Database.postgresql? || Redmine::Database.mysql?

    sleeper = Redmine::Database.postgresql? ? 'SELECT pg_sleep(30)' : 'SELECT SLEEP(30)'

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pcf_with_statement_timeout(2) do
      # MySQL aborts SLEEP() without raising, PostgreSQL raises. Either way the call
      # has to come back on time; that is what is being tested.
      ActiveRecord::Base.connection.select_value(sleeper)
    rescue ActiveRecord::StatementInvalid
      nil
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(elapsed).to be < 15,
                       'a 2s server side deadline did not stop a 30s query; the guard ' \
                       'on the deepest level is not actually bounding anything'
  end

  it 'hints the join order where the optimiser needs it' do
    query = unfiltered_query
    query.add_filter('a_specific_parent_tracker_id', '=', ["#{Tracker.first.id}:3"])

    if Redmine::Database.mysql?
      expect(query.statement).to include('STRAIGHT_JOIN')
    else
      expect(query.statement).not_to include('STRAIGHT_JOIN')
    end
  end

  it 'keeps the settings form inside the same cap' do
    partial = File.read(
      File.expand_path('../app/views/settings/_parent_child_filters_settings.html.erb', __dir__)
    )

    # The form and the query must not disagree about the maximum, so the form
    # reads the constant rather than repeating a literal range.
    expect(partial).to include('MAX_DEPTH')
    expect(partial).not_to match(/\(1\.\.\d+\)/)
  end
end
