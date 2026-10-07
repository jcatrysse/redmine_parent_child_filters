# frozen_string_literal: true

require_relative 'spec_helper'

# Jan, 2026-10-07: "none" is offered in the dropdown of the status filters whose
# relative may be missing. Redmine's :list_status type has "any" but no "none", so
# those filters get a type of their own: :list_status plus "none". The root and
# whole-tree status filters keep :list_status, because there the relative always
# exists and "none" would always be empty (see any_none_spec.rb).
RSpec.describe 'none in the dropdown of the status filters' do
  let(:query) { IssueQuery.new(:name => '_') }
  let(:type) { RedmineParentChildFilters::Patches::QueryInclude::STATUS_WITH_NONE }

  WITH_NONE = %w[
    parent_status_id a_parent_status_id
    child_status_id a_child_status_id
    tree_parent_status_id tree_child_status_id
  ].freeze

  WITHOUT_NONE = %w[root_status_id tree_status_id].freeze

  it 'offers every status operator Redmine offers, plus none' do
    operators = Query.operators_by_filter_type[type]

    expect(operators).to include('!*')
    expect(operators - ['!*']).to eq(Query.operators_by_filter_type[:list_status])
  end

  it 'puts none just before any, as Redmine does on its optional lists' do
    operators = Query.operators_by_filter_type[type]

    expect(operators.index('!*')).to eq(operators.index('*') - 1)
  end

  it 'leaves Redmine\'s own status filter alone' do
    expect(Query.operators_by_filter_type[:list_status]).not_to include('!*')
    expect(query.available_filters['status_id'][:type]).to eq(:list_status)
  end

  WITH_NONE.each do |field|
    it "offers none on #{field}" do
      expect(query.available_filters[field][:type]).to eq(type)
    end
  end

  WITHOUT_NONE.each do |field|
    it "does not offer none on #{field}, whose relative always exists" do
      expect(query.available_filters[field][:type]).to eq(:list_status)
    end
  end

  it 'is sent to the browser with the operator lists' do
    expect(JSON.parse(Query.operators_by_filter_type.to_json)).to include(type.to_s)
  end

  it 'loads the script that renders the type in the filter form' do
    html = RedmineParentChildFilters::Hooks.instance.view_layouts_base_html_head(:controller => nil)

    expect(html).to include('plugin_assets/redmine_parent_child_filters/pcf_filters')
  end

  it 'still validates, and none needs no value' do
    q = unfiltered_query
    q.add_filter('child_status_id', '!*', [''])

    expect(q).to be_valid
    expect { q.issue_count }.not_to raise_error
  end
end
