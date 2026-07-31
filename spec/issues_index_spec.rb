# frozen_string_literal: true

require_relative 'spec_helper'

# End to end check that the issue list still renders. The previous helper patch
# pushed QueriesHelper into ActionView::Base and IssuesController by hand; core
# already exposes it to both, and getting that wrong only shows up here.
RSpec.describe 'issues index' do
  let(:session) { ActionDispatch::Integration::Session.new(Rails.application) }

  it 'renders the filter dropdown with the plugin filters' do
    session.get '/issues'

    expect(session.response.status).to eq(200)
    expect(session.response.body).to include('add_filter_select')
    expect(session.response.body).to include('value="tree_tracker_id"')
    expect(session.response.body).to include(I18n.t(:label_filter_group_parent_child))
  end

  it 'applies a plugin filter from the query string' do
    session.get '/issues', :params => {
      :set_filter => 1,
      :f => ['tree_has_parent_or_child'],
      :op => {'tree_has_parent_or_child' => '='},
      :v => {'tree_has_parent_or_child' => ['1']}
    }

    expect(session.response.status).to eq(200)
  end

  it 'does not break on a crafted filter value' do
    session.get '/issues', :params => {
      :set_filter => 1,
      :f => ['tree_tracker_id'],
      :op => {'tree_tracker_id' => '='},
      :v => {'tree_tracker_id' => ['1) UNION SELECT id FROM users WHERE (1=1']}
    }

    expect(session.response.status).to eq(200)
  end
end
