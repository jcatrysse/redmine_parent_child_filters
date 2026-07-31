# frozen_string_literal: true

require_relative 'spec_helper'

# Every filter is executed against the database. A filter that builds invalid
# SQL, or that trips over NULL semantics, fails here rather than in production.
RSpec.describe IssueQuery do
  PCF_SPEC_FILTERS = %w[
    root_id root_tracker_id root_status_id
    parent_tracker_id parent_status_id
    a_parent_tracker_id a_parent_status_id
    a_specific_parent_tracker_id a_specific_parent_status_id
    child_tracker_id child_status_id
    a_child_tracker_id a_child_status_id
    tree_has_parent_or_child tree_tracker_id tree_status_id
    tree_parent_tracker_id tree_parent_status_id
    tree_child_tracker_id tree_child_status_id
  ].freeze

  let(:project)  { Project.find(1) }
  let(:tracker_a) { project.trackers.sorted[0] }
  let(:tracker_b) { project.trackers.sorted[1] }
  let(:tracker_c) { project.trackers.sorted[2] }
  let(:status_open)   { IssueStatus.where(:is_closed => false).sorted.first }
  let(:status_other)  { IssueStatus.where(:is_closed => false).sorted.second }
  let(:status_closed) { IssueStatus.where(:is_closed => true).sorted.first }

  describe 'registration' do
    it 'registers every filter when the settings enable them' do
      expect(IssueQuery.new.available_filters.keys).to include(*PCF_SPEC_FILTERS)
    end

    it 'omits a filter when its setting is disabled' do
      with_plugin_settings('enable_tree_tracker_id_filter' => '0') do
        expect(IssueQuery.new.available_filters.keys).not_to include('tree_tracker_id')
        expect(IssueQuery.new.available_filters.keys).to include('tree_status_id')
      end
    end
  end

  # Guards against SQL that only ever ran as a Ruby string in the old test suite.
  describe 'operator coverage' do
    PCF_SPEC_FILTERS.each do |field|
      it "executes every operator of #{field}" do
        query = unfiltered_query
        type = query.available_filters[field][:type]

        Query.operators_by_filter_type[type].each do |operator|
          values = sample_values_for(field, operator, query)
          candidate = unfiltered_query
          candidate.add_filter(field, operator, values)

          expect(candidate).to be_valid, "#{field} #{operator}: #{candidate.errors.full_messages.join(', ')}"
          expect { candidate.issue_count }.not_to raise_error, "#{field} #{operator} raised"
        end
      end
    end
  end

  describe 'hierarchy semantics' do
    # root (A/open) -> mid (B/other) -> leaf (C/closed), plus a standalone issue.
    let!(:root)       { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:mid)        { create_issue(project: project, tracker: tracker_b, status: status_other, parent: root) }
    let!(:leaf)       { create_issue(project: project, tracker: tracker_c, status: status_closed, parent: mid) }
    let!(:standalone) { create_issue(project: project, tracker: tracker_a, status: status_open) }

    it 'matches the direct parent tracker' do
      ids = issue_ids_for('parent_tracker_id' => ['=', [tracker_b.id.to_s]])
      expect(ids).to include(leaf.id)
      expect(ids).not_to include(root.id, mid.id, standalone.id)
    end

    it 'keeps parentless issues when negating the direct parent tracker' do
      ids = issue_ids_for('parent_tracker_id' => ['!', [tracker_b.id.to_s]])
      expect(ids).to include(root.id, mid.id, standalone.id)
      expect(ids).not_to include(leaf.id)
    end

    it 'matches any ancestor tracker' do
      ids = issue_ids_for('a_parent_tracker_id' => ['=', [tracker_a.id.to_s]])
      expect(ids).to include(mid.id, leaf.id)
      expect(ids).not_to include(root.id, standalone.id)
    end

    it 'matches the root tracker, including issues that are their own root' do
      ids = issue_ids_for('root_tracker_id' => ['=', [tracker_a.id.to_s]])
      expect(ids).to include(root.id, mid.id, leaf.id, standalone.id)
    end

    it 'matches a parent at a specific depth' do
      ids = issue_ids_for('a_specific_parent_tracker_id' => ['=', ["#{tracker_a.id}:2"]])
      expect(ids).to include(leaf.id)
      expect(ids).not_to include(mid.id, root.id, standalone.id)
    end

    it 'matches issues having a child in a given status' do
      ids = issue_ids_for('child_status_id' => ['=', [status_other.id.to_s]])
      expect(ids).to include(root.id)
      expect(ids).not_to include(mid.id, leaf.id, standalone.id)
    end

    # Regression: the subquery used to select parent_id without filtering NULLs.
    # A NULL in the value list makes NOT IN evaluate to UNKNOWN for every row, so
    # the filter silently degenerated into "has no parent" and returned exactly
    # the top level issues.
    it 'excludes issues having a child in a given status when negated' do
      ids = issue_ids_for('child_status_id' => ['!', [status_other.id.to_s]])

      expect(ids).not_to include(root.id), 'root has a child in that status and must be excluded'
      expect(ids).to include(leaf.id), 'leaf has no children at all and must be included'
      expect(ids).to include(mid.id, standalone.id)
    end

    it 'matches the whole tree on a tracker held by one of its members' do
      ids = issue_ids_for('tree_tracker_id' => ['=', [tracker_c.id.to_s]])
      expect(ids).to include(root.id, mid.id, leaf.id)
      expect(ids).not_to include(standalone.id)
    end

    it 'separates hierarchies from standalone issues' do
      in_tree = issue_ids_for('tree_has_parent_or_child' => ['=', ['1']])
      alone   = issue_ids_for('tree_has_parent_or_child' => ['=', ['0']])

      expect(in_tree).to include(root.id, mid.id, leaf.id)
      expect(in_tree).not_to include(standalone.id)
      expect(alone).to include(standalone.id)
      expect(alone).not_to include(root.id, mid.id, leaf.id)
    end

    it 'matches trees through a matching child, including standalone issues' do
      ids = issue_ids_for('tree_child_tracker_id' => ['=', [tracker_b.id.to_s]])
      expect(ids).to include(root.id, mid.id, leaf.id)
      expect(ids).not_to include(standalone.id)
    end

    it 'combines the child tracker and child status filters on the same child' do
      ids = issue_ids_for(
        'child_tracker_id' => ['=', [tracker_b.id.to_s]],
        'child_status_id' => ['=', [status_other.id.to_s]]
      )
      expect(ids).to include(root.id)

      # No child is both tracker B and closed, so nothing matches.
      none = issue_ids_for(
        'child_tracker_id' => ['=', [tracker_b.id.to_s]],
        'child_status_id' => ['=', [status_closed.id.to_s]]
      )
      expect(none).not_to include(root.id, mid.id)
    end
  end

  # Mirror image of the "any parent" filters: they look down the subtree instead
  # of up the ancestry, at any depth rather than at direct children only.
  describe 'any descendant filters' do
    # root -> mid (B/open) -> leaf (C/closed), plus an unrelated standalone issue.
    let!(:root)       { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:mid)        { create_issue(project: project, tracker: tracker_b, status: status_open, parent: root) }
    let!(:leaf)       { create_issue(project: project, tracker: tracker_c, status: status_closed, parent: mid) }
    let!(:standalone) { create_issue(project: project, tracker: tracker_a, status: status_open) }

    it 'reaches past the direct children' do
      deep = issue_ids_for('a_child_tracker_id' => ['=', [tracker_c.id.to_s]])
      direct = issue_ids_for('child_tracker_id' => ['=', [tracker_c.id.to_s]])

      expect(deep).to include(root.id, mid.id)
      expect(direct).to include(mid.id)
      expect(direct).not_to include(root.id), 'the grandchild is not a direct child of root'
    end

    it 'is the mirror of the any ancestor filter' do
      ancestors_of_leaf = issue_ids_for('a_parent_tracker_id' => ['=', [tracker_a.id.to_s]])
      descendants_of_root = issue_ids_for('a_child_tracker_id' => ['=', [tracker_c.id.to_s]])

      expect(ancestors_of_leaf).to include(mid.id, leaf.id)
      expect(descendants_of_root).to include(root.id, mid.id)
      expect(descendants_of_root).not_to include(leaf.id, standalone.id)
    end

    it 'matches a descendant status at any depth' do
      ids = issue_ids_for('a_child_status_id' => ['c', ['']])

      expect(ids).to include(root.id, mid.id)
      expect(ids).not_to include(leaf.id, standalone.id)
    end

    it 'means "has no matching descendant" when negated, like the other filters' do
      ids = issue_ids_for('a_child_tracker_id' => ['!', [tracker_c.id.to_s]])

      expect(ids).to include(leaf.id, standalone.id)
      expect(ids).not_to include(root.id, mid.id)
    end

    it 'describes the same descendant while both filters ask for a match' do
      both = issue_ids_for(
        'a_child_tracker_id' => ['=', [tracker_c.id.to_s]],
        'a_child_status_id' => ['=', [status_closed.id.to_s]]
      )
      expect(both).to include(root.id, mid.id)

      # root has a tracker C descendant and an open descendant, but no single
      # descendant that is both.
      neither = issue_ids_for(
        'a_child_tracker_id' => ['=', [tracker_c.id.to_s]],
        'a_child_status_id' => ['=', [status_open.id.to_s]]
      )
      expect(neither).not_to include(root.id, mid.id)
    end

    it 'stays out of the subquery of the direct child filters' do
      query = unfiltered_query
      query.add_filter('child_tracker_id', '=', [tracker_b.id.to_s])
      query.add_filter('a_child_tracker_id', '=', [tracker_c.id.to_s])

      expect(query.issues.map(&:id)).to include(root.id)
    end
  end

  # "Child tracker is not X" used to mean "has a child that is not X", which
  # matched a story that did have an X child as long as it had another one too,
  # and never matched a story with no children at all. It now means "has no
  # child that is X", like the child status and both tree child filters.
  describe 'negated child filters' do
    # dev = the tracker a story is expected to have work under,
    # test = the tracker a story is expected to be verified by.
    let(:dev)  { tracker_b }
    let(:test) { tracker_c }

    let!(:with_both) { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:with_dev)  { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:with_test) { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:childless) { create_issue(project: project, tracker: tracker_a, status: status_open) }

    before do
      create_issue(project: project, tracker: dev, status: status_open, parent: with_both)
      create_issue(project: project, tracker: test, status: status_open, parent: with_both)
      create_issue(project: project, tracker: dev, status: status_open, parent: with_dev)
      create_issue(project: project, tracker: test, status: status_open, parent: with_test)
    end

    it 'finds the issues missing a child of that tracker' do
      ids = issue_ids_for('child_tracker_id' => ['!', [test.id.to_s]])

      expect(ids).to include(with_dev.id, childless.id)
      expect(ids).not_to include(with_both.id, with_test.id)
    end

    it 'still allows "has a child of another tracker" through the complement set' do
      others = project.trackers.where.not(:id => test.id).ids.map(&:to_s)
      ids = issue_ids_for('child_tracker_id' => ['=', others])

      expect(ids).to include(with_both.id, with_dev.id)
      expect(ids).not_to include(with_test.id, childless.id)
    end

    it 'reads the same way as the child status filter' do
      by_tracker = issue_ids_for('child_tracker_id' => ['!', [test.id.to_s]])
      by_status = issue_ids_for('child_status_id' => ['!', [status_closed.id.to_s]])

      # Neither excludes an issue merely for having no children.
      expect(by_tracker).to include(childless.id)
      expect(by_status).to include(childless.id)
    end

    it 'evaluates the two child filters independently once one is negated' do
      ids = issue_ids_for(
        'child_tracker_id' => ['!', [test.id.to_s]],
        'child_status_id' => ['=', [status_open.id.to_s]]
      )

      # has no test child, and has an open child
      expect(ids).to include(with_dev.id)
      expect(ids).not_to include(with_both.id, with_test.id, childless.id)
    end

    it 'keeps the same child rule while both filters ask for a match' do
      query = unfiltered_query
      query.add_filter('child_tracker_id', '=', [dev.id.to_s])
      query.add_filter('child_status_id', '=', [status_open.id.to_s])

      # One subquery over the children, carrying both conditions.
      expect(query.statement.scan(/FROM #{Issue.table_name} child/).size).to eq(1)
      expect(query.statement).to match(/child\.tracker_id IN \([\d,]+\) AND child\.status_id IN \([\d,]+\)/)
    end
  end

  # A tracker filter and a status filter that both range over a set of relatives
  # have to agree on which relative they mean. The direct parent, the root and
  # the depth based filters need no rule: there is only one such relative.
  describe 'pairs describing the same relative' do
    # epic (A/open) -> story (B/other) -> task (C/open). Two open statuses, since
    # Redmine refuses to attach an open issue to a closed parent.
    let!(:epic)  { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:story) { create_issue(project: project, tracker: tracker_b, status: status_other, parent: epic) }
    let!(:task)  { create_issue(project: project, tracker: tracker_c, status: status_open, parent: story) }

    it 'requires one ancestor to satisfy both a_parent filters' do
      # task has a tracker B ancestor (story) and a status_open ancestor (epic),
      # but no ancestor that is both.
      split = issue_ids_for(
        'a_parent_tracker_id' => ['=', [tracker_b.id.to_s]],
        'a_parent_status_id' => ['=', [status_open.id.to_s]]
      )
      expect(split).not_to include(task.id)

      same = issue_ids_for(
        'a_parent_tracker_id' => ['=', [tracker_b.id.to_s]],
        'a_parent_status_id' => ['=', [status_other.id.to_s]]
      )
      expect(same).to include(task.id)
    end

    it 'requires one tree member to satisfy both tree filters' do
      split = issue_ids_for(
        'tree_tracker_id' => ['=', [tracker_b.id.to_s]],
        'tree_status_id' => ['=', [status_open.id.to_s]]
      )
      expect(split).not_to include(epic.id, story.id, task.id)

      same = issue_ids_for(
        'tree_tracker_id' => ['=', [tracker_b.id.to_s]],
        'tree_status_id' => ['=', [status_other.id.to_s]]
      )
      expect(same).to include(epic.id, story.id, task.id)
    end

    it 'requires one parent within the tree to satisfy both tree parent filters' do
      # story is a parent, tracker B, status_other.
      same = issue_ids_for(
        'tree_parent_tracker_id' => ['=', [tracker_b.id.to_s]],
        'tree_parent_status_id' => ['=', [status_other.id.to_s]]
      )
      expect(same).to include(epic.id, story.id, task.id)

      split = issue_ids_for(
        'tree_parent_tracker_id' => ['=', [tracker_b.id.to_s]],
        'tree_parent_status_id' => ['=', [status_open.id.to_s]]
      )
      expect(split).not_to include(epic.id, story.id, task.id)
    end

    it 'requires one child within the tree to satisfy both tree child filters' do
      # story is a child, tracker B, status_other.
      same = issue_ids_for(
        'tree_child_tracker_id' => ['=', [tracker_b.id.to_s]],
        'tree_child_status_id' => ['=', [status_other.id.to_s]]
      )
      expect(same).to include(epic.id, story.id, task.id)

      split = issue_ids_for(
        'tree_child_tracker_id' => ['=', [tracker_b.id.to_s]],
        'tree_child_status_id' => ['=', [status_open.id.to_s]]
      )
      expect(split).not_to include(epic.id, story.id, task.id)
    end

    it 'leaves the pair independent once one side is negated' do
      query = unfiltered_query
      query.add_filter('a_parent_tracker_id', '!', [tracker_c.id.to_s])
      query.add_filter('a_parent_status_id', '=', [status_open.id.to_s])

      # Two separate quantifiers rather than one merged subquery.
      expect(query.statement.scan(/FROM #{Issue.table_name} AS ancestor/).size).to eq(2)
      # story has no tracker C ancestor and does have a status_open ancestor.
      expect(query.issues.map(&:id)).to include(story.id)
    end
  end

  # Redmine offers "has been", "has never been" and "changed from" on every
  # status filter. They used to be silently ignored here.
  describe 'status history operators' do
    before { skip 'this Redmine has no history operators' unless history_operators? }

    let!(:parent) { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:child)  { create_issue(project: project, tracker: tracker_b, status: status_open, parent: parent) }

    before do
      # Move the child through a second status and back, leaving a journal.
      child.init_journal(User.current)
      child.status = status_other
      child.save!
      child.reload.init_journal(User.current)
      child.status = status_open
      child.save!
    end

    it 'matches a child whose status has been the given one' do
      ids = issue_ids_for('child_status_id' => ['ev', [status_other.id.to_s]])
      expect(ids).to include(parent.id)
    end

    it 'does not match on a status the child never had' do
      ids = issue_ids_for('child_status_id' => ['ev', [status_closed.id.to_s]])
      expect(ids).not_to include(parent.id)
    end

    it 'reads "has never been" as "no child that has ever been"' do
      ids = issue_ids_for('child_status_id' => ['!ev', [status_other.id.to_s]])
      expect(ids).not_to include(parent.id)

      ids = issue_ids_for('child_status_id' => ['!ev', [status_closed.id.to_s]])
      expect(ids).to include(parent.id)
    end

    it 'matches a child whose status changed from the given one' do
      ids = issue_ids_for('child_status_id' => ['cf', [status_other.id.to_s]])
      expect(ids).to include(parent.id)
    end

    it 'works the same way for ancestors and descendants' do
      expect(issue_ids_for('a_child_status_id' => ['ev', [status_other.id.to_s]])).to include(parent.id)
      expect(issue_ids_for('a_parent_status_id' => ['ev', [status_open.id.to_s]])).to include(child.id)
    end
  end

  # "any root" and "no root" are degenerate by nature: every issue belongs to a
  # tree, its own if it has no relatives.
  describe 'root_id presence operators' do
    it 'shows every issue for "any"' do
      expect(issue_ids_for('root_id' => ['*', ['']])).to eq(all_visible_issue_ids)
    end

    it 'shows no issue for "none"' do
      expect(issue_ids_for('root_id' => ['!*', ['']])).to eq([])
    end

    it 'does not depend on root_id being populated' do
      query = unfiltered_query
      query.add_filter('root_id', '*', [''])
      expect(query.statement).not_to include('root_id')
    end
  end

  describe 'empty and unusable values' do
    it 'matches nothing for a positive operator without a usable id' do
      query = unfiltered_query
      query.add_filter('tree_tracker_id', '=', ['not-an-id'])
      expect(query.issue_count).to eq(0)
    end

    it 'matches everything for a negative operator without a usable id' do
      query = unfiltered_query
      query.add_filter('tree_tracker_id', '!', ['not-an-id'])
      expect(query.issue_count).to eq(all_visible_issue_ids.size)
    end
  end

  def with_plugin_settings(overrides)
    previous = Setting.plugin_redmine_parent_child_filters
    Setting.plugin_redmine_parent_child_filters = previous.merge(overrides)
    yield
  ensure
    Setting.plugin_redmine_parent_child_filters = previous
  end

  def sample_values_for(field, operator, query)
    return [''] if %w[o c * !*].include?(operator)

    case field
    when 'root_id'
      [Issue.first.id.to_s]
    when 'tree_has_parent_or_child'
      ['1']
    when /tracker_id\z/
      field.start_with?('a_specific') ? ["#{Tracker.first.id}:1"] : [Tracker.first.id.to_s]
    when /status_id\z/
      field.start_with?('a_specific') ? ["#{IssueStatus.first.id}:1"] : [IssueStatus.first.id.to_s]
    else
      [query.available_filters[field][:values].to_a.first&.last.to_s]
    end
  end

  # Values at different depths describe different ancestors. The filter used to
  # collapse them onto the smallest depth, silently answering a different
  # question than the one asked.
  describe 'depth based parent filters' do
    # epic (A) -> feature (B) -> story (C) -> task (A)
    let!(:epic)    { create_issue(project: project, tracker: tracker_a, status: status_open) }
    let!(:feature) { create_issue(project: project, tracker: tracker_b, status: status_open, parent: epic) }
    let!(:story)   { create_issue(project: project, tracker: tracker_c, status: status_open, parent: feature) }
    let!(:task)    { create_issue(project: project, tracker: tracker_a, status: status_open, parent: story) }

    it 'matches one depth' do
      expect(issue_ids_for('a_specific_parent_tracker_id' => ['=', ["#{tracker_c.id}:1"]])).to include(task.id)
      expect(issue_ids_for('a_specific_parent_tracker_id' => ['=', ["#{tracker_b.id}:2"]])).to include(task.id)
      expect(issue_ids_for('a_specific_parent_tracker_id' => ['=', ["#{tracker_a.id}:3"]])).to include(task.id)
    end

    it 'does not match the right tracker at the wrong depth' do
      expect(issue_ids_for('a_specific_parent_tracker_id' => ['=', ["#{tracker_c.id}:2"]])).not_to include(task.id)
    end

    it 'honours every selected depth instead of collapsing to the smallest' do
      # story is at depth 1 from task, epic at depth 3. Neither tracker sits at
      # the other's depth, so collapsing onto depth 1 would lose the second.
      ids = issue_ids_for(
        'a_specific_parent_tracker_id' => ['=', ["#{tracker_c.id}:1", "#{tracker_a.id}:3"]]
      )
      expect(ids).to include(task.id)

      only_wrong_depths = issue_ids_for(
        'a_specific_parent_tracker_id' => ['=', ["#{tracker_a.id}:1", "#{tracker_c.id}:3"]]
      )
      expect(only_wrong_depths).not_to include(task.id)
    end

    it 'builds one join chain per selected depth' do
      query = unfiltered_query
      query.add_filter('a_specific_parent_tracker_id', '=', ["#{tracker_c.id}:1", "#{tracker_a.id}:3"])

      expect(pcf_issue_joins(query.statement)).to eq(4) # 1 + 3
      expect(query.statement).to include(' OR ')
    end

    it 'negates the whole selection' do
      ids = issue_ids_for('a_specific_parent_tracker_id' => ['!', ["#{tracker_c.id}:1"]])
      expect(ids).not_to include(task.id)
      expect(ids).to include(epic.id, feature.id)
    end

    it 'still refuses a depth beyond the configured maximum' do
      query = unfiltered_query
      query.add_filter('a_specific_parent_tracker_id', '=', ["#{tracker_a.id}:99"])

      expect(query.statement).to include('1=0')
      expect(pcf_issue_joins(query.statement)).to eq(0)
    end

    it 'keeps the usable half of a partly malformed selection' do
      query = unfiltered_query
      query.add_filter('a_specific_parent_tracker_id', '=', ["#{tracker_c.id}:1", 'junk', "#{tracker_a.id}:99"])

      expect(pcf_issue_joins(query.statement)).to eq(1)
      expect(query.issues.map(&:id)).to include(task.id)
    end
  end
end
