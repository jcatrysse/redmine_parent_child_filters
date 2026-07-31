# frozen_string_literal: true

require_relative 'spec_helper'

# The plugin adds Redmine's "is not" operator to date filters. Operators belong to
# a filter *type*, not to a filter, so this is deliberately wider than the two
# fields the feature was asked for: every filter Redmine types as :date gains it,
# on every query class. These specs pin down exactly how wide, so the
# documentation can say it and a future Redmine cannot widen it unnoticed.
RSpec.describe 'the is not operator on dates' do
  let(:operators) { Query.operators_by_filter_type }

  it 'adds it to the date type' do
    expect(operators[:date]).to include('!')
  end

  # :date_past is the type Redmine uses for timestamps that can only be in the
  # past. Leaving it alone is what keeps created_on, updated_on, closed_on and
  # spent_on out of scope.
  it 'leaves the date_past type alone' do
    expect(operators[:date_past]).not_to include('!')
  end

  # The patch replaces the hash with a copy holding one new :date array, so every
  # other type must still be the very same object. Object identity is the precise
  # statement of "touched nothing else", and unlike a hard coded list it does not
  # depend on which operators a given Redmine version offers.
  it 'touches no operator list other than :date' do
    untouched = operators.except(:date).transform_values(&:object_id)

    RedmineParentChildFilters::Patches::QueryInclude.apply!

    expect(Query.operators_by_filter_type.except(:date).transform_values(&:object_id))
      .to eq(untouched)
  end

  it 'is idempotent and adds the operator once' do
    before = operators[:date].dup

    RedmineParentChildFilters::Patches::QueryInclude.apply!

    expect(Query.operators_by_filter_type[:date]).to eq(before)
    expect(Query.operators_by_filter_type[:date].count('!')).to eq(1)
  end

  # Left unfrozen on purpose: another plugin may legitimately append to the list.
  it 'leaves the list appendable' do
    expect(operators[:date]).not_to be_frozen
  end

  # Where the operator sits decides where it appears in the dropdown. Directly
  # after "<=" puts "is not" beside "is", which is where Redmine keeps it for
  # every other filter type.
  it 'places the operator beside the other equality operators' do
    expect(operators[:date].first(4)).to eq(['=', '>=', '<=', '!'])
  end

  describe 'on the issue list' do
    let(:with_date)    { create_issue(:project => Project.find(1)) }
    let(:other_date)   { create_issue(:project => Project.find(1)) }
    let(:without_date) { create_issue(:project => Project.find(1)) }

    before do
      with_date.update_columns(:due_date => '2020-01-01')
      other_date.update_columns(:due_date => '2020-06-01')
      without_date.update_columns(:due_date => nil)
    end

    %w[start_date due_date].each do |field|
      it "offers it on #{field}" do
        expect(unfiltered_query.available_filters[field][:type]).to eq(:date)
      end
    end

    # An issue with no due date is "not 2020-01-01", the same way an unassigned
    # issue is "not John". Redmine's own sql_for_field spells the NULL out; this
    # asserts the plugin did not accidentally get a version that does not.
    it 'keeps issues without a date' do
      query = unfiltered_query
      query.add_filter('due_date', '!', ['2020-01-01'])

      ids = query.issues.map(&:id)
      expect(ids).to include(without_date.id, other_date.id)
      expect(ids).not_to include(with_date.id)
      expect(query.statement).to include('IS NULL')
    end
  end

  # Date custom fields are typed :date too, so they gain the operator as well.
  # This is the part the plugin never advertised, and the part most likely to
  # break silently, since custom field filters build a very different subquery.
  describe 'on a date custom field' do
    let!(:custom_field) do
      IssueCustomField.create!(:name => 'PcfDateOperatorProbe', :field_format => 'date',
                               :is_filter => true, :is_for_all => true,
                               :tracker_ids => Tracker.pluck(:id))
    end
    let(:field) { "cf_#{custom_field.id}" }

    it 'offers the operator' do
      expect(unfiltered_query.available_filters[field][:type]).to eq(:date)
      expect(unfiltered_query.available_filters[field]).not_to be_nil
    end

    it 'builds SQL a database accepts' do
      query = unfiltered_query
      query.add_filter(field, '!', ['2020-01-01'])

      expect { query.issue_count }.not_to raise_error
    end

    it 'keeps issues that have no value for the field' do
      issue = create_issue(:project => Project.find(1))
      matching = create_issue(:project => Project.find(1))
      matching.custom_field_values = {custom_field.id.to_s => '2020-01-01'}
      matching.save!

      query = unfiltered_query
      query.add_filter(field, '!', ['2020-01-01'])
      ids = query.issues.map(&:id)

      expect(ids).to include(issue.id)
      expect(ids).not_to include(matching.id)
    end
  end

  # Other query classes share the operator hash. Their own date columns are
  # :date_past so they are unaffected, but their date custom fields are not, and
  # nothing there may break.
  describe 'on another query class' do
    it 'does not offer it on spent_on' do
      expect(TimeEntryQuery.new(:name => '_').available_filters['spent_on'][:type]).to eq(:date_past)
    end

    it 'still builds a working query' do
      query = TimeEntryQuery.new(:name => '_')
      query.filters = {}
      query.add_filter('spent_on', '>=', ['2020-01-01'])

      expect { query.results_scope.count }.not_to raise_error
    end
  end
end
