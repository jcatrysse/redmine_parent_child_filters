# frozen_string_literal: true

require_relative 'spec_helper'

# The previous implementation replaced Redmine's filters_options_for_select with
# a copy taken from Redmine 4.x and pulled IssuesHelper into QueriesHelper. On
# Redmine 6.1 and later that raises "cyclic include detected" at boot, and on
# earlier versions it silently dropped core's own filter groups.
RSpec.describe 'filters dropdown' do
  let(:view) { ActionView::Base.empty }

  before do
    view.extend(ApplicationHelper)
    view.extend(QueriesHelper)
    view.extend(Redmine::I18n)
  end

  it 'does not create a cyclic include between the query helpers' do
    expect(QueriesHelper.included_modules).not_to include(IssuesHelper)
  end

  # Compared against what Redmine itself produces rather than against a list of
  # group names: the set of core groups differs between 5.0, 5.1 and 6.x, and
  # the property that matters is that our patch drops none of them.
  it 'keeps every group Redmine builds for its own filters' do
    core_only = IssueQuery.new(:name => '_')
    core_only.instance_variable_set(
      :@available_filters,
      core_only.available_filters.except(*pcf_plugin_filter_names(core_only))
    )

    expected = optgroups(view.filters_options_for_select(core_only))
    actual = optgroups(view.filters_options_for_select(IssueQuery.new(:name => '_')))

    expect(expected).not_to be_empty
    expect(actual).to include(*expected)
  end

  def optgroups(html)
    html.scan(/<optgroup label="([^"]+)"/).flatten
  end

  # Everything this plugin registers, grouped or not.
  def pcf_plugin_filter_names(query)
    previous = Setting.plugin_redmine_parent_child_filters
    all_off = previous.keys.grep(/\Aenable_/).to_h { |key| [key, '0'] }
    Setting.plugin_redmine_parent_child_filters = previous.merge(all_off)
    query.available_filters.keys - IssueQuery.new.available_filters.keys
  ensure
    Setting.plugin_redmine_parent_child_filters = previous
  end

  it 'lists the plugin filters in their own group' do
    html = view.filters_options_for_select(IssueQuery.new(:name => '_'))

    expect(html).to include(%(<optgroup label="#{I18n.t(:label_filter_group_parent_child)}"))
    expect(html).to include('value="tree_tracker_id"')
  end

  # The grouped list and the registered list are the same constant, so they
  # cannot drift apart. What can still go wrong is a filter registered under a
  # name that never reaches the group, so the check is done against the rendered
  # HTML rather than against the constant.
  it 'puts every hierarchy filter in the group and no people filter in it' do
    query = IssueQuery.new(:name => '_')
    group = view.filters_options_for_select(query)[
      /<optgroup label="#{Regexp.escape(I18n.t(:label_filter_group_parent_child))}".*?<\/optgroup>/m
    ]
    grouped = group.to_s.scan(/value="([^"]+)"/).flatten

    hierarchy = RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods::FILTER_ORDER
    expect(grouped.sort).to eq((hierarchy & query.available_filters.keys).sort)
    expect(grouped).not_to include('involved_id', 'mentioned_id', 'involved_or_mentioned_id')
  end

  it 'restores the query filters after rendering' do
    query = IssueQuery.new(:name => '_')
    before = query.available_filters.keys
    view.filters_options_for_select(query)

    expect(query.available_filters.keys).to eq(before)
  end

  it 'falls back to Redmine untouched for queries without plugin filters' do
    expect { view.filters_options_for_select(TimeEntryQuery.new(:name => '_')) }.not_to raise_error
  end
end
