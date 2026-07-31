# frozen_string_literal: true

require_relative 'spec_helper'

# add_available_filter replaces whatever sits under the name it is given. If a
# future Redmine, or another plugin, ships a filter called child_status_id, this
# plugin must step aside rather than change what that filter means. All 23
# filters go through one registration path so none of them can forget to.
RSpec.describe 'filter registration' do
  # Every filter this plugin adds, discovered by switching them all off.
  def plugin_filters
    previous = Setting.plugin_redmine_parent_child_filters
    all_off = previous.keys.grep(/\Aenable_/).to_h { |key| [key, '0'] }
    Setting.plugin_redmine_parent_child_filters = previous.merge(all_off)
    without = IssueQuery.new.available_filters.keys
    Setting.plugin_redmine_parent_child_filters = previous
    IssueQuery.new.available_filters.keys - without
  end

  it 'registers 23 filters, hierarchy and people alike' do
    expect(plugin_filters.size).to eq(23)
    expect(plugin_filters).to include('child_status_id', 'involved_id', 'mentioned_id')
  end

  # The guard, exercised on every filter rather than a sample: a name that is
  # already taken keeps its original value.
  it 'never replaces a filter that already exists' do
    plugin_filters.each do |name|
      query = IssueQuery.new(:name => '_')
      query.available_filters # force the real registration
      sentinel = Object.new
      query.instance_variable_get(:@available_filters)[name] = sentinel

      query.send(:pcf_register_filter, name, :type => :list, :values => [])

      expect(query.instance_variable_get(:@available_filters)[name])
        .to be(sentinel), "#{name} was overwritten"
    end
  end

  it 'says so in the log, once, rather than failing silently' do
    query = IssueQuery.new(:name => '_')
    query.available_filters
    query.instance_variable_get(:@available_filters)['child_status_id'] = Object.new

    messages = []
    allow(Rails.logger).to receive(:warn) { |message| messages << message }

    3.times { query.send(:pcf_register_filter, 'child_status_id', :type => :list, :values => []) }

    expect(messages.size).to be <= 1
    expect(messages.first).to include('child_status_id') if messages.any?
  end

  # Registration is per query object, so a condition that holds at all holds for
  # every query built afterwards. Logging it each time would bury the log.
  it 'warns at most once per process for the same name' do
    RedmineParentChildFilters.warn_once('pcf-spec-key', 'first')

    messages = []
    allow(Rails.logger).to receive(:warn) { |message| messages << message }
    5.times { RedmineParentChildFilters.warn_once('pcf-spec-key', 'again') }

    expect(messages).to eq([])
  end

  it 'derives the label from the filter name' do
    query = IssueQuery.new(:name => '_')

    plugin_filters.each do |name|
      expect(query.available_filters[name][:name])
        .to eq(I18n.t("label_filter_#{name}")), "#{name} does not use its own label"
    end
  end

  # Loading the plugin twice happens under Rails reloading and when a host
  # application requires init.rb again. Prepending the same module twice is a
  # no-op, but registering twice must be too.
  it 'survives the patches being applied again' do
    before = IssueQuery.new.available_filters.keys

    IssueQuery.prepend(RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods)
    IssueQuery.prepend(RedmineParentChildFilters::Patches::InvolvementFilterPatch::InstanceMethods)
    IssueQuery.prepend(RedmineParentChildFilters::Patches::MentionFilterPatch::InstanceMethods)

    expect(IssueQuery.new.available_filters.keys).to eq(before)
    expect(IssueQuery.ancestors.count(RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods))
      .to eq(1)
  end
end
