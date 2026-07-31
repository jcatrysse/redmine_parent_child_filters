# frozen_string_literal: true

require_relative 'spec_helper'

# Every filter must be switchable off by an administrator, and the switch must
# actually appear in the settings form. Both are easy to forget when adding a
# filter, and neither is visible until someone tries to turn it off.
RSpec.describe 'administration of the filters' do
  PCF_SETTINGS_PARTIAL =
    File.read(File.expand_path('../app/views/settings/_parent_child_filters_settings.html.erb', __dir__)).freeze

  def filters_with(overrides)
    previous = Setting.plugin_redmine_parent_child_filters
    Setting.plugin_redmine_parent_child_filters = previous.merge(overrides)
    IssueQuery.new.available_filters.keys
  ensure
    Setting.plugin_redmine_parent_child_filters = previous
  end

  let(:toggles) { Setting.plugin_redmine_parent_child_filters.keys.grep(/\Aenable_/).sort }
  let(:all_off) { toggles.to_h { |key| [key, '0'] } }
  let(:plugin_filters) { (IssueQuery.new.available_filters.keys - filters_with(all_off)).sort }

  it 'adds filters at all' do
    expect(plugin_filters.size).to be >= 20
  end

  it 'leaves nothing of its own behind when everything is switched off' do
    expect(filters_with(all_off) & plugin_filters).to eq([])
  end

  it 'names one setting per filter, following enable_<filter>_filter' do
    expect(plugin_filters.map { |field| "enable_#{field}_filter" }.sort).to eq(toggles)
  end

  it 'renders a checkbox for every setting' do
    missing = toggles.reject { |key| PCF_SETTINGS_PARTIAL.include?("'#{key}'") }
    expect(missing).to eq([])
  end

  it 'switches each filter off on its own, without touching the others' do
    plugin_filters.each do |field|
      remaining = filters_with("enable_#{field}_filter" => '0')

      expect(remaining).not_to include(field), "#{field} stayed after being switched off"
      expect(remaining).to include(*(plugin_filters - [field])), "switching #{field} off removed others"
    end
  end

  it 'leaves the core filters alone either way' do
    core = %w[status_id tracker_id assigned_to_id author_id subject created_on]
    expect(filters_with(all_off)).to include(*core)
    expect(IssueQuery.new.available_filters.keys).to include(*core)
  end
end
