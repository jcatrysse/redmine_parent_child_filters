# frozen_string_literal: true

require_relative 'spec_helper'

# Filter values arrive straight from the request (v[<field>][]) and are stored
# verbatim in saved queries, so they must never reach the SQL string unescaped.
RSpec.describe 'filter value handling' do
  # A payload with balanced parentheses produces syntactically valid SQL once
  # interpolated, so it executes instead of raising.
  PCF_INJECTION_PAYLOADS = [
    '1) UNION SELECT id FROM users WHERE (1=1',
    "1)) OR (('a'='a",
    '1); DROP TABLE issues; --',
    "1' OR '1'='1"
  ].freeze

  PCF_ID_FILTERS = %w[
    root_tracker_id root_status_id
    parent_tracker_id parent_status_id
    a_parent_tracker_id a_parent_status_id
    child_tracker_id child_status_id
    a_child_tracker_id a_child_status_id
    tree_tracker_id tree_status_id
    tree_parent_tracker_id tree_parent_status_id
    tree_child_tracker_id tree_child_status_id
  ].freeze

  # The statement legitimately contains quotes and UNION of its own: Redmine's
  # visibility condition quotes the module name, and the tree filters union two
  # subqueries. So the assertion is not "the SQL looks clean" but "no fragment of
  # the payload is in it, and the query returns nothing".
  def expect_no_injection(statement, context)
    expect(statement).not_to match(/\busers\b/i), context
    expect(statement).not_to match(/\bDROP\b/i), context
    expect(statement).not_to include('--'), context
    expect(statement).not_to match(/'[^']*=/), context # no quoted comparison from a payload
  end

  PCF_ID_FILTERS.each do |field|
    it "does not let a crafted value reach the SQL of #{field}" do
      PCF_INJECTION_PAYLOADS.each do |payload|
        query = unfiltered_query
        query.add_filter(field, '=', [payload])

        expect_no_injection(query.statement, "#{field}: #{payload}")
        expect { query.issue_count }.not_to raise_error
        # Fail closed: a value that is not an id list is not an id list, so the
        # filter matches nothing rather than matching whatever digits it held.
        expect(query.issue_count).to eq(0), "#{field}: #{payload} returned rows"
      end
    end
  end

  # Core reads "1) UNION ..." as the id 1 by scanning for digit runs. Only digits
  # survive either way, so neither can inject, but returning the rows for tracker 1
  # answers a question nobody asked.
  it 'refuses a crafted value rather than reading an id out of it' do
    query = unfiltered_query
    query.add_filter('tree_tracker_id', '=', ['1) UNION SELECT id FROM users WHERE (1=1'])

    expect(query.statement).not_to include('tree.tracker_id IN (1)')
    expect(query.statement).to include('1=0')
    expect(query.statement).not_to match(/\busers\b/i)
  end

  it 'sanitises the companion filter read by child_tracker_id' do
    query = unfiltered_query
    query.add_filter('child_tracker_id', '=', [Tracker.first.id.to_s])
    query.add_filter('child_status_id', '=', ['5) UNION SELECT id FROM users WHERE (1=1'])

    expect_no_injection(query.statement, 'child_status_id companion')
    expect { query.issue_count }.not_to raise_error
  end

  describe 'depth bounded filters' do
    it 'refuses a depth beyond the configured maximum instead of building joins' do
      query = unfiltered_query
      query.add_filter('a_specific_parent_tracker_id', '=', ["#{Tracker.first.id}:999999"])

      expect(pcf_issue_joins(query.statement)).to eq(0)
      expect(query.statement).to include('1=0')
      expect { query.issue_count }.not_to raise_error
    end

    it 'accepts a depth within the configured maximum' do
      query = unfiltered_query
      query.add_filter('a_specific_parent_tracker_id', '=', ["#{Tracker.first.id}:3"])

      expect(pcf_issue_joins(query.statement)).to eq(3)
      expect { query.issue_count }.not_to raise_error
    end

    it 'does not raise on a value without a depth' do
      query = unfiltered_query
      query.add_filter('a_specific_parent_status_id', '=', ['5'])

      expect { query.issue_count }.not_to raise_error
      expect(query.issue_count).to eq(0)
    end

    it 'does not raise on a mix of well formed and malformed values' do
      query = unfiltered_query
      query.add_filter('a_specific_parent_status_id', '=', ['5', "#{IssueStatus.first.id}:2", 'x:y'])

      expect { query.issue_count }.not_to raise_error
      expect(pcf_issue_joins(query.statement)).to eq(2)
    end
  end

  # The principal filters take ids and resolve them to logins, and the mention
  # filter puts a login into both a LIKE pattern and a regular expression.
  describe 'principal filters' do
    PCF_PRINCIPAL_FILTERS = %w[involved_id mentioned_id involved_or_mentioned_id].freeze

    PCF_PRINCIPAL_FILTERS.each do |field|
      # A crafted value is rejected, not repaired.
      #
      # This spec used to assert the opposite: that every payload produced exactly
      # the SQL of the plain value "1", because each of them carries the digit 1 and
      # nothing else numeric. That was safe — only digits ever reached the SQL — but
      # it meant "1) UNION SELECT ..." was answered as "principal 1", which is a
      # question nobody asked. The hierarchy filters always rejected such a value;
      # the principal filters now do too, so there is one rule instead of two.
      it "rejects a crafted value rather than reading digits out of it on #{field}" do
        plain = unfiltered_query
        plain.add_filter(field, '=', ['1'])

        empty = unfiltered_query
        empty.add_filter(field, '=', ['not-an-id'])

        PCF_INJECTION_PAYLOADS.each do |payload|
          query = unfiltered_query
          query.add_filter(field, '=', [payload])

          expect(query.statement).to eq(empty.statement), "#{field}: #{payload}"
          expect(query.statement).not_to eq(plain.statement), "#{field}: #{payload}"
          expect(query.statement).not_to match(/\bDROP\b/i)
          expect { query.issue_count }.not_to raise_error
          expect(query.issues).to eq([]), "#{field}: #{payload}"
        end
      end

      it "matches nothing rather than everything for an unusable value on #{field}" do
        query = unfiltered_query
        query.add_filter(field, '=', ['not-a-principal'])
        expect(query.issue_count).to eq(0)
      end
    end

    it 'escapes a login holding LIKE wildcards' do
      user = User.new(:firstname => 'Wild', :lastname => 'Card', :mail => 'wild@example.net')
      user.login = 'a_b'
      user.save!(:validate => false)

      hit  = create_mention_issue("ping @a_b now")
      miss = create_mention_issue("ping @axb now")

      ids = issue_ids_for('mentioned_id' => ['=', [user.id.to_s]])
      expect(ids).to include(hit.id)
      expect(ids).not_to include(miss.id), '_ must be a literal underscore, not a LIKE wildcard'
    end

    it 'escapes a login holding regular expression metacharacters' do
      user = User.new(:firstname => 'Meta', :lastname => 'Char', :mail => 'meta@example.net')
      user.login = 'a.b'
      user.save!(:validate => false)

      hit  = create_mention_issue("ping @a.b now")
      miss = create_mention_issue("ping @axb now")

      ids = issue_ids_for('mentioned_id' => ['=', [user.id.to_s]])
      expect(ids).to include(hit.id)
      expect(ids).not_to include(miss.id)
    end

    # A login is not user input, but it is attacker influenced on an instance
    # where self registration is open, so it must not be able to break the SQL.
    it 'survives a login built to break out of the pattern' do
      user = User.new(:firstname => 'Quote', :lastname => 'Break', :mail => 'quote@example.net')
      user.login = "x') OR 1=1 --"
      user.save!(:validate => false)

      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [user.id.to_s])

      expect { query.issue_count }.not_to raise_error
      expect(query.issue_count).to eq(0)
    end

    # Selecting many principals used to add one LIKE per login to every row.
    it 'does not add a comparison per principal' do
      ids = User.active.where.not(:login => '').limit(10).pluck(:id).map(&:to_s)
      skip 'needs several users' if ids.size < 3
      skip 'no REGEXP on SQLite' if Redmine::Database.sqlite?

      one = unfiltered_query.tap { |q| q.add_filter('mentioned_id', '=', [ids.first]) }
      many = unfiltered_query.tap { |q| q.add_filter('mentioned_id', '=', ids) }
      matcher = Redmine::Database.postgresql? ? /~\*/ : /REGEXP/

      # One regular expression per searched column, whatever the selection size.
      expect(one.statement.scan(matcher).size).to eq(2)
      expect(many.statement.scan(matcher).size).to eq(2)
      expect(many.statement.scan(/LIKE|ILIKE/).size).to eq(one.statement.scan(/LIKE|ILIKE/).size)
      expect { many.issue_count }.not_to raise_error
    end

    def create_mention_issue(description)
      Issue.create!(
        :project => Project.find(1),
        :tracker => Project.find(1).trackers.first,
        :status => IssueStatus.sorted.first,
        :author => User.find(1),
        :subject => 'security mention',
        :description => description,
        :priority => IssuePriority.active.first
      )
    end
  end
end
