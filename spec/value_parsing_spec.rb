# frozen_string_literal: true

require_relative 'spec_helper'

# A filter value arrives from the request as a string and is stored verbatim in a
# saved query. Only digits ever reach the SQL, so none of these can inject, but
# reading an id out of something that is not an id answers a question nobody
# asked: a mistyped url or a saved query written by an older version quietly
# returns real rows.
RSpec.describe 'filter value parsing' do
  let(:query) { unfiltered_query }

  # [value, expected ids or nil]
  PCF_VALUES = [
    # accepted
    ['1',              [1]],
    ['42',             [42]],
    ['1,2,3',          [1, 2, 3]],
    [' 1 , 2 ',        [1, 2]],   # whitespace around a value is tolerated...
    ["1\t",            [1]],      # ...including a tab
    ['7,7',            [7]],      # duplicates collapse
    ['2147483647',     [2_147_483_647]],
    ['99999999999999999999', [99_999_999_999_999_999_999]], # a legal id that matches nothing

    # rejected
    ['',               nil],
    ['   ',            nil],
    [nil,              nil],
    ['0',              nil],      # no record has id 0
    ['-1',             nil],
    ['+1',             nil],
    ['1.0',            nil],
    ['1 OR 2',         nil],      # core would read this as 1,2
    ['user-123',       nil],      # core would read this as 123
    ['1;2',            nil],
    [',',              nil],
    ['1,',             nil],
    [',1',             nil],
    ['3,x,8',          nil],      # one bad element rejects the value
    ['1) UNION SELECT id FROM users WHERE (1=1', nil],
    ["1' OR '1'='1",   nil],
    ['0x10',           nil],
    ['１２',            nil],      # full width digits: \d is ASCII only in Ruby
    ['١٢',             nil],      # Arabic-Indic digits
    ["1\n2",           nil]     # but whitespace *inside* a value is not
  ].freeze

  PCF_VALUES.each do |value, expected|
    it "reads #{value.inspect} as #{expected.inspect}" do
      result = query.send(:pcf_id_list, [value])

      expect(result).to eq(expected&.join(',')), "#{value.inspect} became #{result.inspect}"
    end
  end

  it 'drops the unusable values out of a multi select and keeps the rest' do
    expect(query.send(:pcf_id_list, ['1', 'nonsense', '3'])).to eq('1,3')
  end

  it 'yields nothing usable when every value is unusable' do
    expect(query.send(:pcf_id_list, %w[nonsense also-nonsense])).to be_nil
  end

  # What "nothing usable" then means for the query: no rows for a positive
  # operator, every row for a negation, which is what "there is no such relative"
  # says when the relative was never named.
  describe 'a filter left with nothing usable' do
    it 'matches nothing when asking for a match' do
      query.add_filter('child_tracker_id', '=', ['1 OR 2'])

      expect(query.statement).to include('1=0')
      expect(query.issue_count).to eq(0)
    end

    it 'matches everything when asking for the absence of one' do
      query.add_filter('child_tracker_id', '!', ['1 OR 2'])

      expect(query.statement).to include('1=1')
      expect(query.issue_count).to eq(all_visible_issue_ids.size)
    end
  end

  describe 'the depth syntax' do
    # [value, accepted?]
    PCF_DEPTH_VALUES = [
      ['1:1',   true],
      ['42:3',  true],
      ['1:0',   false],  # level 0 is the issue itself, not an ancestor
      ['0:1',   false],  # no tracker has id 0
      ['1',     false],  # no level at all
      ['1:',    false],
      [':1',    false],
      ['1:1:1', false],
      ['1,2:1', false],  # a list is not a single id here
      ['-1:1',  false],
      ['1:-1',  false],
      ['x:y',   false],
      ['1:99999', false] # above the ceiling
    ].freeze

    PCF_DEPTH_VALUES.each do |value, accepted|
      it "#{accepted ? 'accepts' : 'refuses'} #{value.inspect}" do
        parsed = query.send(:pcf_parse_depth_values, [value])

        expect(parsed.empty?).to eq(!accepted), "#{value.inspect} parsed to #{parsed.inspect}"
      end
    end

    it 'never raises, whatever it is given' do
      weird = ['', nil, ':', '::', 'a', '1:1:1:1', '0:0', "\0", '1:１']
      expect { query.send(:pcf_parse_depth_values, weird) }.not_to raise_error
      expect(query.send(:pcf_parse_depth_values, weird)).to eq({})
    end
  end

  # root_id takes one comma separated string rather than a list, which is the one
  # filter where the list syntax is user facing.
  describe 'the root filter' do
    it 'accepts a comma separated list' do
      root = create_issue
      child = create_issue(:parent => root)

      expect(issue_ids_for('root_id' => ['=', ["#{root.id},#{root.id}"]])).to include(root.id, child.id)
    end

    it 'refuses a crafted list rather than reading ids out of it' do
      query.add_filter('root_id', '=', ['1) UNION SELECT id FROM users WHERE (1=1'])

      expect(query.statement).to include('1=0')
      expect(query.statement).not_to match(/\busers\b/i)
      expect(query.issue_count).to eq(0)
    end
  end

  # The one filter whose value is a flag rather than an id. The select offers "1"
  # and "0"; anything else is a corrupted saved query or a hand written url.
  describe 'the yes/no filter' do
    PCF_FLAG_VALUES = [
      [['1'],        true],
      [['0'],        false],
      [[],           nil],
      [[''],         nil],
      [nil,          nil],
      [['yes'],      nil],
      [['no'],       nil],
      [['true'],     nil],
      [['10'],       nil],
      [['1 OR 1=1'], nil],
      [%w[1 0],      nil], # the select is single valued; two answers is no answer
      [%w[1 1],      true] # ...but the same answer twice is still that answer
    ].freeze

    PCF_FLAG_VALUES.each do |values, expected|
      it "reads #{values.inspect} as #{expected.inspect}" do
        expect(query.send(:pcf_parse_flag, values)).to eq(expected)
      end
    end

    # Reading an unusable value as "no" would answer the opposite question, which
    # is worse than answering none: every other filter here fails closed.
    it 'matches nothing for an unusable value, and everything under a negation' do
      positive = unfiltered_query
      positive.add_filter('tree_has_parent_or_child', '=', ['yes'])
      expect(positive.statement).to include('1=0')
      expect(positive.issue_count).to eq(0)

      negative = unfiltered_query
      negative.add_filter('tree_has_parent_or_child', '!', ['yes'])
      expect(negative.statement).to include('1=1')
      expect(negative.issue_count).to eq(all_visible_issue_ids.size)
    end

    it 'still answers both real values' do
      # The fixtures carry no parent/child link of their own, so the two sides of
      # this filter have to be created here for the assertion to mean anything.
      parent = create_issue
      child  = create_issue(:parent => parent)
      solo   = create_issue

      linked = issue_ids_for('tree_has_parent_or_child' => ['=', ['1']])
      alone  = issue_ids_for('tree_has_parent_or_child' => ['=', ['0']])

      expect(linked).to include(parent.id, child.id)
      expect(linked).not_to include(solo.id)
      expect(alone).to include(solo.id)
      expect(alone).not_to include(parent.id, child.id)
      expect(linked & alone).to eq([])
    end
  end

  # Principal values read the same way hierarchy ids do. They used to go through
  # core's scan(/\d+/), which turns "1 OR 2" into two real principals.
  describe 'principal values' do
    PCF_PRINCIPAL_VALUES = [
      [['1'],           [1]],
      [%w[1 2],         [1, 2]],
      [['1 OR 2'],      []],
      [['user-123'],    []],
      [['0'],           []],
      [['-1'],          []],
      [[''],            []],
      [['１'],          []], # full width digits are not \d in Ruby
      [%w[1 bogus],     [1]] # one bad element drops itself, not the whole list
    ].freeze

    PCF_PRINCIPAL_VALUES.each do |values, expected|
      it "reads #{values.inspect} as #{expected.inspect}" do
        expect(query.send(:pcf_principal_ids, values)).to eq(expected)
      end
    end

    it 'still expands me to the current user and their groups' do
      expected = [User.current.id] + User.current.group_ids
      expect(query.send(:pcf_principal_ids, ['me'])).to eq(expected.uniq.sort)
    end
  end
end
