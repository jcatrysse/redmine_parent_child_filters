# frozen_string_literal: true

require_relative 'spec_helper'

# Redmine moves the subtasks of a moved issue without a journal. The plugin gives
# them one, so their history, Redmine's own "has been" and the project filters can
# all tell where they came from.
RSpec.describe 'journaling subtasks moved along with their parent' do
  let(:origin)      { pcf_project('pcf-journal-origin') }
  let(:destination) { pcf_project('pcf-journal-destination') }
  let(:mover)       { User.find(2) }

  let!(:parent)     { create_issue(project: origin) }
  let!(:child)      { create_issue(project: origin, parent: parent) }
  let!(:grandchild) { create_issue(project: origin, parent: child) }

  def pcf_project(identifier)
    project = Project.create!(:name => identifier, :identifier => identifier, :is_public => true)
    project.trackers = Tracker.all
    project.enabled_module_names = ['issue_tracking']
    project
  end

  def with_setting(value)
    previous = Setting.plugin_redmine_parent_child_filters
    Setting.plugin_redmine_parent_child_filters = previous.merge('journal_subtask_moves' => value)
    yield
  ensure
    Setting.plugin_redmine_parent_child_filters = previous
  end

  # A move from the issue form: a fresh object and a journal for the parent.
  def move_parent(journal: true)
    issue = Issue.find(parent.id)
    issue.init_journal(mover) if journal
    issue.project = destination
    issue.save!
  end

  def project_moves(issue)
    JournalDetail.joins(:journal)
                 .where(:journals => {:journalized_type => 'Issue', :journalized_id => issue.id},
                        :property => 'attr', :prop_key => 'project_id')
  end

  it 'journals the move of a subtask, by the user who moved the parent' do
    move_parent

    details = project_moves(child).to_a
    expect(details.size).to eq(1)
    detail = details.first
    expect([detail.old_value, detail.value]).to eq([origin.id.to_s, destination.id.to_s])
    expect(detail.journal.user).to eq(mover)
    expect(detail.journal.notes).to be_blank
  end

  it 'journals every level below, not only the direct subtasks' do
    move_parent

    expect(grandchild.reload.project_id).to eq(destination.id)
    details = project_moves(grandchild).to_a
    expect(details.size).to eq(1)
    expect(details.first.journal.user).to eq(mover)
  end

  it 'journals the parent exactly once, as Redmine does' do
    move_parent
    expect(project_moves(parent).count).to eq(1)
  end

  it 'lets the original project filter find the subtasks' do
    move_parent

    expect(issue_ids_for('first_project_id' => ['=', [origin.id.to_s]]))
      .to include(parent.id, child.id, grandchild.id)
  end

  # The parent's move already notified; a mail per subtask would be noise.
  it 'sends no notification for the subtask journals' do
    journals = []
    allow(Journal).to receive(:new).and_wrap_original do |original, *args, &block|
      original.call(*args, &block).tap { |journal| journals << journal }
    end

    move_parent

    by_issue = journals.group_by(&:journalized_id)
    expect(by_issue[parent.id].map(&:notify?)).to all(be(true))
    expect(by_issue[child.id].map(&:notify?)).to eq([false])
    expect(by_issue[grandchild.id].map(&:notify?)).to eq([false])
  end

  # A script that moves the parent silently moves its subtasks silently too, so
  # the two histories cannot disagree.
  it 'journals nothing when the parent move itself is not journaled' do
    move_parent(journal: false)

    expect(child.reload.project_id).to eq(destination.id)
    expect(project_moves(parent)).to be_empty
    expect(project_moves(child)).to be_empty
  end

  # Redmine only moves the subtasks that were in the parent's project.
  it 'leaves a subtask that stays in its own project alone' do
    Setting.cross_project_subtasks = 'system'
    other = pcf_project('pcf-journal-other')
    elsewhere = create_issue(project: other, parent: parent)

    move_parent

    expect(elsewhere.reload.project_id).to eq(other.id)
    expect(project_moves(elsewhere)).to be_empty
  end

  it 'does nothing when switched off' do
    with_setting('0') { move_parent }

    expect(child.reload.project_id).to eq(destination.id)
    expect(project_moves(child)).to be_empty
    expect(project_moves(parent).count).to eq(1)
  end

  it 'is switched on by default' do
    expect(Redmine::Plugin.find(:redmine_parent_child_filters).settings[:default]['journal_subtask_moves']).to be(true)
    expect(RedmineParentChildFilters.journal_subtask_moves?).to be(true)
  end

  it 'leaves nothing behind once the move is over' do
    move_parent
    expect(Thread.current[RedmineParentChildFilters::Patches::SubtaskMoveJournalPatch::MOVER]).to be_nil
  end

  it 'leaves nothing behind when the move fails' do
    issue = Issue.find(parent.id)
    issue.init_journal(mover)
    issue.project = destination
    allow(Journal).to receive(:new).and_raise(RuntimeError, 'boom')

    expect { issue.save! }.to raise_error(RuntimeError, 'boom')
    expect(Thread.current[RedmineParentChildFilters::Patches::SubtaskMoveJournalPatch::MOVER]).to be_nil
  end

  it 'does not journal a project change outside a parent move' do
    issue = Issue.find(child.id)
    issue.project = destination
    issue.save!

    expect(project_moves(child)).to be_empty
  end
end
