# frozen_string_literal: true

require_relative 'spec_helper'

# "Issues where I am the assignee, the author or a watcher" is the query
# Redmine cannot express, because it joins filters with AND.
RSpec.describe 'involved filter' do
  let(:project) { Project.find(1) }
  let(:me)      { User.find(2) }  # jsmith, member of project 1
  let(:other)   { User.find(3) }  # dlopper

  def create_issue_for(author:, assigned_to: nil, watchers: [])
    issue = Issue.new(
      :project => project,
      :tracker => project.trackers.first,
      :status => IssueStatus.sorted.first,
      :author => author,
      :assigned_to => assigned_to,
      :subject => 'involvement test',
      :priority => IssuePriority.active.first
    )
    issue.save!
    watchers.each { |w| Watcher.create!(:watchable => issue, :user => w) }
    issue.reload
  end

  describe 'registration' do
    it 'is available' do
      expect(IssueQuery.new.available_filters.keys).to include('involved_id')
    end

    it 'offers me first, then the principals' do
      values = IssueQuery.new.available_filters['involved_id'][:values]
      expect(values.first).to eq(["<< #{I18n.t(:label_me)} >>", 'me'])
      expect(values.map(&:second)).to include(me.id.to_s)
    end

    it 'can be switched off' do
      previous = Setting.plugin_redmine_parent_child_filters
      Setting.plugin_redmine_parent_child_filters = previous.merge('enable_involved_id_filter' => '0')
      expect(IssueQuery.new.available_filters.keys).not_to include('involved_id')
    ensure
      Setting.plugin_redmine_parent_child_filters = previous
    end

    it 'stays out of the parent and child group in the dropdown' do
      view = ActionView::Base.empty
      view.extend(ApplicationHelper)
      view.extend(QueriesHelper)
      view.extend(Redmine::I18n)

      html = view.filters_options_for_select(IssueQuery.new(:name => '_'))
      group = html[/<optgroup label="#{Regexp.escape(I18n.t(:label_filter_group_parent_child))}".*?<\/optgroup>/m]

      expect(html).to include('value="involved_id"')
      expect(group).not_to include('value="involved_id"')
    end
  end

  describe 'matching' do
    let!(:authored)   { create_issue_for(author: me) }
    let!(:assigned)   { create_issue_for(author: other, assigned_to: me) }
    let!(:watched)    { create_issue_for(author: other, watchers: [me]) }
    let!(:unrelated)  { create_issue_for(author: other, assigned_to: other) }
    let!(:unassigned) { create_issue_for(author: other) }

    it 'returns each role in a single filter row' do
      ids = issue_ids_for('involved_id' => ['=', [me.id.to_s]])

      expect(ids).to include(authored.id, assigned.id, watched.id)
      expect(ids).not_to include(unrelated.id, unassigned.id)
    end

    it 'needs three separate filters to be reproduced, none of which is enough on its own' do
      by_author = issue_ids_for('author_id' => ['=', [me.id.to_s]])
      by_assignee = issue_ids_for('assigned_to_id' => ['=', [me.id.to_s]])

      expect(by_author).not_to include(assigned.id, watched.id)
      expect(by_assignee).not_to include(authored.id, watched.id)
    end

    it 'substitutes me for the current user' do
      User.current = me
      expect(issue_ids_for('involved_id' => ['=', ['me']]))
        .to eq(issue_ids_for('involved_id' => ['=', [me.id.to_s]]))
    end

    it 'matches nothing for me when not logged in' do
      User.current = User.anonymous
      expect(issue_ids_for('involved_id' => ['=', ['me']])).not_to include(authored.id, assigned.id, watched.id)
    end

    it 'accepts several principals at once' do
      ids = issue_ids_for('involved_id' => ['=', [me.id.to_s, other.id.to_s]])
      expect(ids).to include(authored.id, assigned.id, watched.id, unrelated.id, unassigned.id)
    end

    # NULL IN (...) is UNKNOWN, and NOT UNKNOWN is UNKNOWN, so an unguarded
    # assignee leg drops every unassigned issue from the negated filter.
    it 'keeps unassigned issues when negated' do
      ids = issue_ids_for('involved_id' => ['!', [me.id.to_s]])

      expect(ids).to include(unassigned.id), 'unassigned issues must not vanish under NOT'
      expect(ids).to include(unrelated.id)
      expect(ids).not_to include(authored.id, assigned.id, watched.id)
    end

    it 'matches nothing usable when no principal is given' do
      query = unfiltered_query
      query.add_filter('involved_id', '=', ['not-a-principal'])
      expect(query.issue_count).to eq(0)
    end
  end

  describe 'watcher visibility' do
    let!(:watched_by_other) { create_issue_for(author: User.find(1), watchers: [other]) }

    it 'hides the watcher leg from a user without view_issue_watchers' do
      Role.find(1).remove_permission!(:view_issue_watchers)
      User.current = me

      expect(me.allowed_to?(:view_issue_watchers, project)).to be false
      expect(issue_ids_for('involved_id' => ['=', [other.id.to_s]])).not_to include(watched_by_other.id)
    end

    it 'shows it to a user who may see watchers' do
      User.current = me

      expect(me.allowed_to?(:view_issue_watchers, project)).to be true
      expect(issue_ids_for('involved_id' => ['=', [other.id.to_s]])).to include(watched_by_other.id)
    end

    it 'always lets a user find what they watch themselves' do
      Role.find(1).remove_permission!(:view_issue_watchers)
      own = create_issue_for(author: User.find(1), watchers: [me])
      User.current = me

      expect(issue_ids_for('involved_id' => ['=', ['me']])).to include(own.id)
    end
  end

  describe 'groups' do
    # An issue assigned to a group I belong to is mine, which is how Redmine
    # itself treats assigned_to_id and watcher_id for the "me" value.
    it 'counts an issue assigned to one of my groups as mine' do
      Setting.issue_group_assignment = '1'
      group = Group.create!(:lastname => 'Involvement group')
      group.users << me
      Member.create!(:project => project, :principal => group, :roles => [Role.find(1)])

      group_assigned = create_issue_for(author: other, assigned_to: group)
      User.current = me.reload

      expect(User.current.group_ids).to include(group.id)
      expect(issue_ids_for('involved_id' => ['=', ['me']])).to include(group_assigned.id)
    end
  end
end
