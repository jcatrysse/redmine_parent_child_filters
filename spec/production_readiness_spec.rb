# frozen_string_literal: true

require_relative 'spec_helper'

# The filters are exercised elsewhere through IssueQuery. These specs check the
# ways a filter reaches a user in production: the issue list, the Gantt, the
# exports, the API and a saved query, plus the one thing that must never happen,
# an issue from a project the user cannot see appearing in a result.
RSpec.describe 'production paths' do
  let(:project)  { Project.find(1) }
  let(:member)   { User.find(2) }   # jsmith, member of project 1 only
  let(:session)  { ActionDispatch::Integration::Session.new(Rails.application) }

  def login(user = 'admin', password = 'admin')
    session.post '/login', :params => {:username => user, :password => password}
  end

  def plugin_filters
    previous = Setting.plugin_redmine_parent_child_filters
    all_off = previous.keys.grep(/\Aenable_/).to_h { |k| [k, '0'] }
    Setting.plugin_redmine_parent_child_filters = previous.merge(all_off)
    without = IssueQuery.new.available_filters.keys
    Setting.plugin_redmine_parent_child_filters = previous
    IssueQuery.new.available_filters.keys - without
  end

  describe 'a filter reaches every view' do
    let(:params) do
      {:set_filter => 1, :f => ['tree_tracker_id'],
       :op => {'tree_tracker_id' => '='}, :v => {'tree_tracker_id' => [Tracker.first.id.to_s]}}
    end

    before { login }

    it 'works on the issue list' do
      session.get '/issues', :params => params
      expect(session.response.status).to eq(200)
    end

    it 'works on the Gantt' do
      session.get '/issues/gantt', :params => params
      expect(session.response.status).to eq(200)
    end

    it 'works on the calendar' do
      session.get '/issues/calendar', :params => params
      expect(session.response.status).to eq(200)
    end

    it 'works for the CSV export' do
      session.get '/issues.csv', :params => params
      expect(session.response.status).to eq(200)
      expect(session.response.headers['Content-Type']).to include('text/csv')
    end

    it 'works for the PDF export' do
      session.get '/issues.pdf', :params => params
      expect(session.response.status).to eq(200)
    end

    it 'works over the REST API' do
      Setting.rest_api_enabled = '1'
      session.get '/issues.json', :params => params.merge(:key => User.find(1).api_key)

      expect(session.response.status).to eq(200)
      expect { JSON.parse(session.response.body) }.not_to raise_error
    end

    it 'works for the Atom feed' do
      session.get '/issues.atom', :params => params
      expect(session.response.status).to eq(200)
    end
  end

  describe 'a saved query' do
    let!(:parent) { create_issue(project: project) }
    let!(:child)  { create_issue(project: project, parent: parent) }

    it 'survives being stored and read back' do
      query = IssueQuery.new(:name => 'Saved involvement', :user => User.find(1), :project => project)
      query.filters = {}
      query.add_filter('involved_id', '=', [member.id.to_s])
      query.add_filter('child_tracker_id', '=', [child.tracker_id.to_s])
      query.save!

      before_ids = query.issues.map(&:id).sort
      reloaded = IssueQuery.find(query.id)

      expect(reloaded.filters.keys).to contain_exactly('involved_id', 'child_tracker_id')
      expect(reloaded.issues.map(&:id).sort).to eq(before_ids)
    end

    it 'is rendered without error from its own url' do
      query = IssueQuery.new(:name => 'Saved tree', :user => User.find(1),
                             :visibility => Query::VISIBILITY_PUBLIC)
      query.filters = {}
      query.add_filter('tree_has_parent_or_child', '=', ['1'])
      query.save!

      login
      session.get '/issues', :params => {:query_id => query.id}
      expect(session.response.status).to eq(200)
    end
  end

  # The outer query is always Issue.visible, but a filter that joined its way
  # around that scope would leak. This checks every filter at once.
  describe 'project visibility' do
    let!(:secret) do
      secret = Project.create!(:name => 'Secret', :identifier => 'secret-project', :is_public => false)
      secret.trackers = Tracker.all
      secret.enabled_module_names = ['issue_tracking']
      secret
    end

    let!(:secret_parent) { create_issue(project: secret) }
    let!(:secret_child)  { create_issue(project: secret, parent: secret_parent) }

    it 'is invisible to a non member to begin with' do
      User.current = member
      expect(Issue.visible.pluck(:id)).not_to include(secret_parent.id, secret_child.id)
    end

    it 'never surfaces through any filter, positive or negative' do
      fields = plugin_filters
      expect(fields).not_to be_empty
      User.current = member
      hidden = [secret_parent.id, secret_child.id]

      fields.each do |field|
        query = IssueQuery.new(:name => '_')
        query.filters = {}
        type = query.available_filters[field][:type]

        Query.operators_by_filter_type[type].each do |operator|
          candidate = IssueQuery.new(:name => '_')
          candidate.filters = {}
          candidate.add_filter(field, operator, sample_value_for(field, operator))
          next unless candidate.valid?

          ids = candidate.issues.map(&:id)
          expect(ids & hidden).to eq([]), "#{field} #{operator} leaked a hidden issue"
        end
      end
    end
  end

  def sample_value_for(field, operator)
    return [''] if %w[o c * !*].include?(operator)

    case field
    when 'root_id' then [Issue.first.id.to_s]
    when /\Aa_specific_parent_tracker/ then ["#{Tracker.first.id}:1"]
    when /\Aa_specific_parent_status/ then ["#{IssueStatus.first.id}:1"]
    when /involved|mentioned/ then [User.find(3).id.to_s]
    when /tracker_id\z/ then [Tracker.first.id.to_s]
    when /status_id\z/ then [IssueStatus.first.id.to_s]
    else ['1'] # tree_has_parent_or_child, whose values are '1' and '0'
    end
  end
end
