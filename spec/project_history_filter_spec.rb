# frozen_string_literal: true

require_relative 'spec_helper'

# "Every issue ever created in project A" is the question these filters answer.
# Redmine journals every move, so the answer is in the history: the oldest
# project change says where an issue came from, and an issue that never moved is
# still where it was created.
RSpec.describe 'project history filters' do
  let(:origin)      { pcf_project('pcf-origin') }
  let(:middle)      { pcf_project('pcf-middle') }
  let(:destination) { pcf_project('pcf-destination') }
  let(:outsider)    { User.find(3) } # dlopper, member of none of these projects

  def pcf_project(identifier)
    project = Project.create!(:name => identifier, :identifier => identifier, :is_public => true)
    project.trackers = Tracker.all
    project.enabled_module_names = ['issue_tracking']
    project
  end

  # Moves the way Redmine does from the issue form: a fresh issue object per
  # request, so every move gets a journal of its own. Reusing one object would
  # put both changes in the same journal, because init_journal memoises it.
  def move(issue, project)
    issue = Issue.find(issue.id)
    issue.init_journal(User.find(1))
    issue.project = project
    issue.save!
    issue.reload
  end

  def project_change_journals(issue)
    Journal.joins(:details)
           .where(:journalized_type => 'Issue', :journalized_id => issue.id)
           .where(:journal_details => {:property => 'attr', :prop_key => 'project_id'})
           .order(:id)
  end

  def ids_for(field, operator, projects)
    issue_ids_for(field => [operator, Array(projects).map { |p| p.is_a?(Project) ? p.id.to_s : p }])
  end

  describe 'registration' do
    it 'adds both filters to the global issue list' do
      expect(IssueQuery.new.available_filters.keys).to include('project_history_id', 'first_project_id')
    end

    # Core offers no project filter inside a project; "which of these came from
    # elsewhere" is exactly the question asked there.
    it 'adds both filters inside a project too' do
      expect(IssueQuery.new(:project => origin).available_filters.keys)
        .to include('project_history_id', 'first_project_id')
    end

    it 'gives the history filter the history operators where Redmine has them' do
      type = IssueQuery.new.available_filters['project_history_id'][:type]
      expect(type).to eq(history_operators? ? :list_with_history : :list)
    end

    it "offers core's project list, my projects included" do
      Member.create!(:principal => outsider, :project => origin, :role_ids => [Role.givable.first.id])
      User.current = outsider

      values = IssueQuery.new.available_filters['first_project_id'][:values].map(&:second)
      expect(values).to include('mine', origin.id.to_s)
    end

    it 'leaves the core project filter as it is' do
      filter = IssueQuery.new.available_filters['project_id']
      expect(filter[:type]).to eq(:list)
    end

    it 'stays out of the parent and child group in the dropdown' do
      view = ActionView::Base.empty
      view.extend(ApplicationHelper)
      view.extend(QueriesHelper)
      view.extend(Redmine::I18n)

      html = view.filters_options_for_select(IssueQuery.new(:name => '_'))
      group = html[/<optgroup label="#{Regexp.escape(I18n.t(:label_filter_group_parent_child))}".*?<\/optgroup>/m]

      expect(html).to include('value="first_project_id"', 'value="project_history_id"')
      expect(group).not_to include('first_project_id', 'project_history_id')
    end
  end

  describe 'first project' do
    let!(:stayed)      { create_issue(project: origin) }
    let!(:moved_once)  { move(create_issue(project: origin), destination) }
    let!(:moved_twice) { move(move(create_issue(project: origin), middle), destination) }
    let!(:arrived)     { move(create_issue(project: middle), destination) }
    let!(:native)      { create_issue(project: destination) }

    it 'finds every issue created in a project, wherever it is now' do
      expect(ids_for('first_project_id', '=', origin)).to eq([stayed, moved_once, moved_twice].map(&:id).sort)
    end

    it 'does not count a project an issue only passed through' do
      expect(ids_for('first_project_id', '=', middle)).to eq([arrived.id])
    end

    it 'does not count the project an issue was moved to' do
      expect(ids_for('first_project_id', '=', destination)).to eq([native.id])
    end

    it 'keeps the original project of an issue that went away and came back' do
      returned = move(move(create_issue(project: origin), destination), origin)

      expect(ids_for('first_project_id', '=', origin)).to include(returned.id)
      expect(ids_for('first_project_id', '=', destination)).not_to include(returned.id)
    end

    it 'negates as a whole: an issue has exactly one first project' do
      ids = ids_for('first_project_id', '!', origin)

      expect(ids).to include(arrived.id, native.id)
      expect(ids).not_to include(stayed.id, moved_once.id, moved_twice.id)
    end

    it 'accepts several projects at once' do
      expect(ids_for('first_project_id', '=', [origin, middle]))
        .to eq([stayed, moved_once, moved_twice, arrived].map(&:id).sort)
    end

    # Redmine moves the subtasks of a moved issue without a journal; the plugin
    # gives them one (spec/subtask_move_journal_spec.rb). Without it, nothing
    # records where they came from and they read as created where they are now.
    it 'finds a subtask that moved along with its parent' do
      parent = create_issue(project: origin)
      child = create_issue(project: origin, parent: parent)
      move(parent, destination)

      expect(child.reload.project_id).to eq(destination.id)
      expect(ids_for('first_project_id', '=', origin)).to include(parent.id, child.id)
      # Redmine's own "has been" reads the same journal.
      expect(ids_for('project_history_id', 'ev', origin)).to include(child.id) if history_operators?
    end

    it 'cannot trace a subtask moved while the journaling was switched off' do
      previous = Setting.plugin_redmine_parent_child_filters
      Setting.plugin_redmine_parent_child_filters = previous.merge('journal_subtask_moves' => '0')
      parent = create_issue(project: origin)
      child = create_issue(project: origin, parent: parent)
      move(parent, destination)

      expect(project_change_journals(child)).to be_empty
      expect(ids_for('first_project_id', '=', origin)).not_to include(child.id)
      expect(ids_for('first_project_id', '=', destination)).to include(child.id)
    ensure
      Setting.plugin_redmine_parent_child_filters = previous
    end

    it 'does see a subtask that was moved on its own' do
      parent = create_issue(project: origin)
      child = move(create_issue(project: origin, parent: parent), destination)

      expect(ids_for('first_project_id', '=', origin)).to include(child.id)
    end

    # The issue history is shown by created_on, then id, and "first" means what
    # the history shows first, not what happened to be inserted first.
    it 'takes the oldest change in the order the history shows it' do
      older, newer = project_change_journals(moved_twice).to_a
      older.update_column(:created_on, newer.created_on + 1.minute)

      expect(ids_for('first_project_id', '=', middle)).to include(moved_twice.id)
      expect(ids_for('first_project_id', '=', origin)).not_to include(moved_twice.id)
    end

    it 'breaks a tie on created_on by id' do
      older, newer = project_change_journals(moved_twice).to_a
      newer.update_column(:created_on, older.created_on)

      expect(ids_for('first_project_id', '=', origin)).to include(moved_twice.id)
      expect(ids_for('first_project_id', '=', middle)).not_to include(moved_twice.id)
    end

    it 'expands my projects the way core does' do
      Member.create!(:principal => outsider, :project => origin, :role_ids => [Role.givable.first.id])
      User.current = outsider
      mine = outsider.memberships.pluck(:project_id).map(&:to_s)

      expect(mine).to include(origin.id.to_s)
      expect(issue_ids_for('first_project_id' => ['=', ['mine']]))
        .to eq(issue_ids_for('first_project_id' => ['=', mine]))
    end

    # One journal holding two project changes, oldest first by detail id.
    it 'reads two changes in one journal in the order they were recorded' do
      issue = create_issue(project: origin)
      issue.init_journal(User.find(1))
      issue.project = middle
      issue.save!
      issue.project = destination
      issue.save!

      expect(project_change_journals(issue).distinct.count).to eq(1)
      expect(ids_for('first_project_id', '=', origin)).to include(issue.id)
      expect(ids_for('first_project_id', '=', middle)).not_to include(issue.id)
    end

    it 'expands my bookmarks the way core does' do
      Redmine::ProjectJumpBox.new(User.current).bookmark_project(middle)
      bookmarks = User.current.bookmarked_project_ids.map(&:to_s)

      expect(bookmarks).to include(middle.id.to_s)
      expect(issue_ids_for('first_project_id' => ['=', ['bookmarks']]))
        .to eq(issue_ids_for('first_project_id' => ['=', bookmarks]))
      expect(issue_ids_for('first_project_id' => ['=', ['bookmarks']])).to include(arrived.id)
    end

    it 'matches nothing for my projects when I have none' do
      User.current = User.anonymous
      expect(issue_ids_for('first_project_id' => ['=', ['mine']])).to eq([])
    end

    it 'works inside a project' do
      query = IssueQuery.new(:name => '_', :project => destination)
      query.filters = {}
      query.add_filter('first_project_id', '=', [origin.id.to_s])

      expect(query.issues.map(&:id).sort).to eq([moved_once.id, moved_twice.id].sort)
    end

    describe 'a move recorded in a journal made private afterwards' do
      before do
        Role.non_member.remove_permission!(:view_private_notes)
        project_change_journals(moved_once).update_all(:private_notes => true)
      end

      it 'is not read for a user who may not see it' do
        User.current = outsider

        expect(ids_for('first_project_id', '=', origin)).not_to include(moved_once.id)
        expect(ids_for('first_project_id', '=', destination)).to include(moved_once.id)
      end

      it 'is read for a user who may' do
        expect(ids_for('first_project_id', '=', origin)).to include(moved_once.id)
      end
    end
  end

  describe 'project history' do
    let!(:stayed)     { create_issue(project: origin) }
    let!(:moved_away) { move(create_issue(project: origin), destination) }
    let!(:native)     { create_issue(project: destination) }

    it 'means the current project for "is"' do
      expect(ids_for('project_history_id', '=', origin)).to eq([stayed.id])
    end

    it 'means not the current project for "is not"' do
      ids = ids_for('project_history_id', '!', origin)
      expect(ids).to include(moved_away.id, native.id)
      expect(ids).not_to include(stayed.id)
    end

    context 'with the history operators', if: Query.operators_by_filter_type.key?(:list_with_history) do
      it 'finds issues that are or have been in a project for "has been"' do
        expect(ids_for('project_history_id', 'ev', origin)).to eq([stayed.id, moved_away.id].sort)
      end

      it 'finds the rest for "has never been"' do
        ids = ids_for('project_history_id', '!ev', origin)
        expect(ids).to include(native.id)
        expect(ids).not_to include(stayed.id, moved_away.id)
      end

      it 'finds only issues that left a project for "changed from"' do
        expect(ids_for('project_history_id', 'cf', origin)).to eq([moved_away.id])
      end

      it "is core's own history SQL" do
        query = unfiltered_query
        query.add_filter('project_history_id', 'ev', [origin.id.to_s])

        expect(query.statement).to include("prop_key = 'project_id'")
      end
    end

    context 'without the history operators', unless: Query.operators_by_filter_type.key?(:list_with_history) do
      it 'drops a history operator that arrives from a hand written url' do
        query = unfiltered_query
        query.add_filter('project_history_id', 'ev', [origin.id.to_s])

        expect { query.issue_count }.not_to raise_error
      end
    end
  end

  describe 'the issue list' do
    let(:session) { ActionDispatch::Integration::Session.new(Rails.application) }
    let!(:moved) { move(create_issue(project: origin), destination) }

    before { session.post '/login', :params => {:username => 'admin', :password => 'admin'} }

    def get_issues(path, field, operator)
      session.get path, :params => {:set_filter => 1, :f => [field], :op => {field => operator},
                                    :v => {field => [origin.id.to_s]}}
      session.response
    end

    it 'renders the original project filter and its result' do
      response = get_issues('/issues', 'first_project_id', '=')

      expect(response.status).to eq(200)
      expect(response.body).to include(I18n.t(:label_filter_first_project_id))
      expect(response.body).to include("issue-#{moved.id}")
    end

    it 'renders the history filter inside a project' do
      operator = history_operators? ? 'ev' : '!'
      response = get_issues("/projects/#{destination.identifier}/issues", 'project_history_id', operator)

      expect(response.status).to eq(200)
      expect(response.body).to include(I18n.t(:label_filter_project_history_id))
      expect(response.body).to include("issue-#{moved.id}")
    end
  end

  describe 'values' do
    let!(:issue) { create_issue(project: origin) }

    %w[first_project_id project_history_id].each do |field|
      it "fails closed on a value that is not a project id in #{field}" do
        query = unfiltered_query
        query.add_filter(field, '=', ['1) UNION SELECT id FROM users WHERE (1=1'])

        expect(query.statement).not_to match(/\busers\b/i)
        expect(query.issue_count).to eq(0)
      end

      it "keeps every issue when #{field} is not anything usable" do
        query = unfiltered_query
        query.add_filter(field, '!', ['x'])

        expect(query.issue_count).to eq(unfiltered_query.issue_count)
      end
    end
  end
end
