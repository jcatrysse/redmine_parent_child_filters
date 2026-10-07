# frozen_string_literal: true

require_relative 'spec_helper'

# The version Redmine shows under Administration > Plugins and the release the
# changelog describes first must be the same, so an administrator reading either
# knows what is installed. Jan, 2026-10-07: this release is 1.2.0, a minor
# release, because it adds "none" to the status filters.
RSpec.describe 'the plugin version' do
  let(:version) { Redmine::Plugin.find(:redmine_parent_child_filters).version }
  let(:changelog) { File.read(File.expand_path('../CHANGELOG.md', __dir__)) }

  it 'is 1.2.0' do
    expect(version).to eq('1.2.0')
  end

  it 'is the release the changelog describes first' do
    expect(changelog[/^## (\S+)/, 1]).to eq(version)
  end

  it 'has an upgrade note in the readme' do
    readme = File.read(File.expand_path('../README.md', __dir__))
    expect(readme).to include("## Upgrading to #{version}")
  end
end
