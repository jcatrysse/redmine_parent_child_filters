# frozen_string_literal: true

require_relative 'spec_helper'

# Redmine 6 and later add every plugin's lib/ to the Zeitwerk autoloader *and*
# mark it eager_load, so in production the whole directory is loaded at boot,
# before anything asks for it. The test environment does not eager load, which
# means a file that only works when required in the right order passes the suite
# and then breaks a production boot. These specs force the situation the test
# environment otherwise hides.
RSpec.describe 'loading the plugin the way production does' do
  it 'eager loads the application without raising' do
    expect { Rails.application.eager_load! }.not_to raise_error
  end

  it 'has every patch applied to the class it patches' do
    expect(IssueQuery.ancestors)
      .to include(RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods)
    expect(IssueQuery.ancestors)
      .to include(RedmineParentChildFilters::Patches::InvolvementFilterPatch::InstanceMethods)
    expect(IssueQuery.ancestors)
      .to include(RedmineParentChildFilters::Patches::MentionFilterPatch::InstanceMethods)
    expect(QueriesHelper.ancestors)
      .to include(RedmineParentChildFilters::Patches::QueriesHelperPatch::InstanceMethods)
  end

  # Zeitwerk raises on a file whose constant name does not match its path. The
  # plugin's lib/ is loaded by init.rb with plain requires, so a mismatch would
  # only surface once Zeitwerk walked the directory itself.
  it 'names every file after the constant it defines' do
    root = File.expand_path('../lib', __dir__)

    Dir.glob("#{root}/**/*.rb").sort.each do |path|
      constant = path.delete_prefix("#{root}/").delete_suffix('.rb').camelize
      expect { constant.constantize }
        .not_to raise_error, "#{path} does not define #{constant}"
    end
  end

  # Every patch is loaded exactly once. Loading a prepend twice is harmless, but
  # a patch that got included instead would silently lose to the method it meant
  # to override.
  it 'prepends each patch once' do
    [RedmineParentChildFilters::Patches::IssueQueryPatch::InstanceMethods,
     RedmineParentChildFilters::Patches::QueriesHelperPatch::InstanceMethods].each do |mod|
      target = mod.name.include?('QueriesHelper') ? QueriesHelper : IssueQuery
      expect(target.ancestors.count(mod)).to eq(1)
    end
  end
end
