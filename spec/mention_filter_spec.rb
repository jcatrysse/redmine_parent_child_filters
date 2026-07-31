# frozen_string_literal: true

require_relative 'spec_helper'

# Mentions are not stored anywhere, so the filter reads the text. These specs
# pin the two things a text search gets wrong if written naively: the word
# boundary, and NULL columns under a negation.
RSpec.describe 'mentioned filter' do
  let(:project) { Project.find(1) }
  let(:me)      { User.find(2) }  # jsmith
  let(:other)   { User.find(3) }  # dlopper

  def create_issue_with(description: nil, notes: nil, private_notes: false,
                        author: User.find(1), assigned_to: nil)
    issue = Issue.new(
      :project => project,
      :tracker => project.trackers.first,
      :status => IssueStatus.sorted.first,
      :author => author,
      :assigned_to => assigned_to,
      :subject => 'mention test',
      :description => description,
      :priority => IssuePriority.active.first
    )
    issue.save!

    if notes
      # Reload first: Redmine bumps lock_version on save, so the in memory copy
      # is stale by the time the journal is added.
      issue = Issue.find(issue.id)
      issue.init_journal(author, notes)
      issue.current_journal.private_notes = private_notes
      issue.save!
    end

    Issue.find(issue.id)
  end

  describe 'registration' do
    it 'offers the mention filters' do
      keys = IssueQuery.new.available_filters.keys
      expect(keys).to include('mentioned_id', 'involved_or_mentioned_id')
    end

    it 'lists users only, since a group has no login to mention' do
      values = IssueQuery.new.available_filters['mentioned_id'][:values]
      expect(values.first).to eq(["<< #{I18n.t(:label_me)} >>", 'me'])
      expect(values.map(&:second)).to include(me.id.to_s)
    end

    it 'can be switched off' do
      previous = Setting.plugin_redmine_parent_child_filters
      Setting.plugin_redmine_parent_child_filters = previous.merge('enable_mentioned_id_filter' => '0')
      expect(IssueQuery.new.available_filters.keys).not_to include('mentioned_id')
    ensure
      Setting.plugin_redmine_parent_child_filters = previous
    end
  end

  describe 'matching' do
    let!(:in_description) { create_issue_with(description: "Hi @#{me.login}, please look at this") }
    let!(:in_notes)       { create_issue_with(description: 'nothing here', notes: "@#{me.login} ping") }
    let!(:at_start)       { create_issue_with(description: "@#{me.login} starts the text") }
    let!(:punctuated)     { create_issue_with(description: "cc @#{me.login}, thanks") }
    let!(:untouched)      { create_issue_with(description: 'no mention at all') }
    let!(:no_description) { create_issue_with(description: nil) }

    it 'finds mentions in the description and in the notes' do
      ids = issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])

      expect(ids).to include(in_description.id, in_notes.id, at_start.id, punctuated.id)
      expect(ids).not_to include(untouched.id, no_description.id)
    end

    it 'substitutes me' do
      User.current = me
      expect(issue_ids_for('mentioned_id' => ['=', ['me']]))
        .to eq(issue_ids_for('mentioned_id' => ['=', [me.id.to_s]]))
    end

    it 'keeps issues without a description when negated' do
      ids = issue_ids_for('mentioned_id' => ['!', [me.id.to_s]])

      expect(ids).to include(no_description.id), 'a NULL description must not swallow the row'
      expect(ids).to include(untouched.id)
      expect(ids).not_to include(in_description.id, in_notes.id)
    end

    it 'matches nothing when the principal cannot be resolved to a login' do
      query = unfiltered_query
      query.add_filter('mentioned_id', '=', ['999999'])
      expect(query.issue_count).to eq(0)
    end
  end

  describe 'word boundaries' do
    let!(:exact)  { create_issue_with(description: "hello @#{me.login} bye") }
    let!(:longer) { create_issue_with(description: "hello @#{me.login}son bye") }
    let!(:email)  { create_issue_with(description: "write to someone@#{me.login}.example") }

    it 'does not match a longer login that starts with the same characters' do
      skip 'SQLite has no REGEXP' if Redmine::Database.sqlite?

      ids = issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])
      expect(ids).to include(exact.id)
      expect(ids).not_to include(longer.id)
    end

    it 'does not match an address that contains the login' do
      skip 'SQLite has no REGEXP' if Redmine::Database.sqlite?

      expect(issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])).not_to include(email.id)
    end

    it 'treats a dot in a login as a literal' do
      skip 'SQLite has no REGEXP' if Redmine::Database.sqlite?

      dotted = User.new(:firstname => 'Jan', :lastname => 'Doe', :mail => 'jan.doe@example.net')
      dotted.login = 'jan.doe'
      dotted.save!

      hit  = create_issue_with(description: 'ping @jan.doe now')
      miss = create_issue_with(description: 'ping @janXdoe now')

      ids = issue_ids_for('mentioned_id' => ['=', [dotted.id.to_s]])
      expect(ids).to include(hit.id)
      expect(ids).not_to include(miss.id)
    end
  end

  describe 'private notes' do
    let!(:mentioned_privately) do
      create_issue_with(description: 'nothing', notes: "@#{me.login} secret", private_notes: true, author: User.find(1))
    end

    it 'is hidden from a user who may not read private notes' do
      Role.find(1).remove_permission!(:view_private_notes)
      User.current = me

      expect(issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])).not_to include(mentioned_privately.id)
    end

    it 'is visible to a user who may' do
      Role.find(1).add_permission!(:view_private_notes)
      User.current = me

      expect(issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])).to include(mentioned_privately.id)
    end
  end

  describe 'involved or mentioned' do
    let!(:assigned)  { create_issue_with(description: 'nothing', assigned_to: me) }
    let!(:mentioned) { create_issue_with(description: "cc @#{me.login}") }
    let!(:neither)   { create_issue_with(description: 'nothing') }

    it 'covers both the roles and the mentions' do
      ids = issue_ids_for('involved_or_mentioned_id' => ['=', [me.id.to_s]])

      expect(ids).to include(assigned.id, mentioned.id)
      expect(ids).not_to include(neither.id)
    end

    it 'is a strict superset of the involved filter' do
      involved = issue_ids_for('involved_id' => ['=', [me.id.to_s]])
      combined = issue_ids_for('involved_or_mentioned_id' => ['=', [me.id.to_s]])

      expect(combined).to include(*involved)
      expect(combined).to include(mentioned.id)
      expect(involved).not_to include(mentioned.id)
    end

    it 'keeps unassigned issues without a description when negated' do
      blank = create_issue_with(description: nil)
      expect(issue_ids_for('involved_or_mentioned_id' => ['!', [me.id.to_s]])).to include(blank.id)
    end
  end

  describe 'edge cases' do
    it 'finds a mention at the start of a line inside a longer note' do
      issue = create_issue_with(description: 'nothing', notes: "First line\n@#{me.login} second line")
      expect(issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])).to include(issue.id)
    end

    it 'finds a mention wrapped in brackets' do
      issue = create_issue_with(description: "see (@#{me.login}) for details")
      expect(issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])).to include(issue.id)
    end

    it 'matches nothing for an anonymous user asking about themselves' do
      create_issue_with(description: "cc @#{me.login}")
      User.current = User.anonymous

      expect(issue_ids_for('mentioned_id' => ['=', ['me']])).to eq([])
      expect(issue_ids_for('involved_or_mentioned_id' => ['=', ['me']])).to eq([])
    end

    it 'ignores a group, which has no login to mention' do
      group = Group.create!(:lastname => 'Mention group')
      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [group.id.to_s])

      expect(query.issue_count).to eq(0)
    end

    # Redmine strips code blocks and quoted replies before notifying; SQL cannot.
    it 'accepts that a mention inside a code block still matches' do
      issue = create_issue_with(description: "```\n@#{me.login}\n```")
      expect(issue_ids_for('mentioned_id' => ['=', [me.id.to_s]])).to include(issue.id)
    end

    it 'serves its values over the remote filter endpoint' do
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.post '/login', :params => {:username => 'admin', :password => 'admin'}
      session.get '/queries/filter', :params => {:name => 'mentioned_id', :type => 'IssueQuery'}

      expect(session.response.status).to eq(200)
      expect(session.response.body).to include(me.login.capitalize).or include('me')
    end
  end
end
