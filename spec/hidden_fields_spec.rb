# frozen_string_literal: true

require_relative 'spec_helper'

# A plugin may hide a core field from a role by removing its filter, which is
# what redmine_issue_field_visibility does for the assignee and the description.
# The people filters must not answer through the back door what that user can
# no longer ask directly: with the assignee filter gone, "Assignee, author or
# watcher" keeps the author and the watchers but not the assignee, and with the
# description filter gone the mention filters read the notes only.
RSpec.describe 'people filters and hidden core fields' do
  let(:project) { Project.find(1) }
  let(:me)      { User.find(2) }  # jsmith
  let(:other)   { User.find(3) }  # dlopper

  def create(assigned_to: nil, description: nil, author: other)
    issue = Issue.new(:project => project, :tracker => project.trackers.first,
                      :status => IssueStatus.sorted.first, :author => author,
                      :assigned_to => assigned_to, :subject => 'hidden field test',
                      :description => description, :priority => IssuePriority.active.first)
    issue.save!
    issue
  end

  # The query as another plugin leaves it after removing the given filters.
  def ids_without(hidden, field, operator, values)
    query = unfiltered_query
    query.available_filters
    hidden.each { |name| query.delete_available_filter(name) }
    query.add_filter(field, operator, values)
    query.issues.map(&:id)
  end

  let!(:assigned)  { create(assigned_to: me) }
  let!(:authored)  { create(author: me) }
  let!(:mentioned) { create(description: "cc @#{me.login}") }

  it 'uses the assignee while the assignee filter is offered' do
    expect(ids_without([], 'involved_id', '=', [me.id.to_s])).to include(assigned.id, authored.id)
  end

  it 'leaves the assignee out when the assignee filter is hidden' do
    ids = ids_without(['assigned_to_id'], 'involved_id', '=', [me.id.to_s])

    expect(ids).not_to include(assigned.id)
    expect(ids).to include(authored.id)
  end

  it 'does not reveal the assignee through "is not" either' do
    ids = ids_without(['assigned_to_id'], 'involved_id', '!', [me.id.to_s])

    expect(ids).to include(assigned.id)
    expect(ids).not_to include(authored.id)
  end

  it 'leaves the assignee out of involved or mentioned too' do
    ids = ids_without(['assigned_to_id'], 'involved_or_mentioned_id', '=', [me.id.to_s])

    expect(ids).not_to include(assigned.id)
    expect(ids).to include(authored.id, mentioned.id)
  end

  it 'searches the description while the description filter is offered' do
    expect(ids_without([], 'mentioned_id', '=', [me.id.to_s])).to include(mentioned.id)
  end

  it 'does not search the description when the description filter is hidden' do
    expect(ids_without(['description'], 'mentioned_id', '=', [me.id.to_s])).not_to include(mentioned.id)
    expect(ids_without(['description'], 'involved_or_mentioned_id', '=', [me.id.to_s])).not_to include(mentioned.id)
  end

  it 'still searches the notes when the description filter is hidden' do
    issue = create(description: 'nothing')
    issue = Issue.find(issue.id)
    issue.init_journal(other, "@#{me.login} please")
    issue.save!

    expect(ids_without(['description'], 'mentioned_id', '=', [me.id.to_s])).to include(issue.id)
  end
end
