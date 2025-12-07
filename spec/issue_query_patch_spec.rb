require_relative 'spec_helper'
require_relative '../lib/redmine_parent_child_filters/patches/issue_query_patch'

RSpec.describe IssueQuery do
  let(:query) { described_class.new }

  describe '#initialize_available_filters_with_pcf' do
    it 'registers the tree tracker filter when enabled' do
      query.initialize_available_filters
      query.initialize_available_filters_with_pcf

      expect(query.available_filters).to have_key('tree_tracker_id')
      expect(query.available_filters['tree_tracker_id'][:label]).to eq(:label_filter_tree_tracker_id)
    end

    it 'registers the tree status filter when enabled' do
      query.initialize_available_filters
      query.initialize_available_filters_with_pcf

      expect(query.available_filters).to have_key('tree_status_id')
      expect(query.available_filters['tree_status_id'][:label]).to eq(:label_filter_tree_status_id)
    end

    it 'exposes tree hierarchy membership as a list with yes/no values' do
      query.initialize_available_filters
      query.initialize_available_filters_with_pcf

      filter = query.available_filters['tree_has_parent_or_child']

      expect(filter[:type]).to eq(:list)
      expect(filter[:values]).to eq([[l(:general_text_yes), '1'], [l(:general_text_no), '0']])
    end
  end

  describe '#sql_for_root_id_field' do
    it 'builds equality conditions for listed root ids' do
      expect(query.sql_for_root_id_field('root_id', '=', ['1,2'])).to eq('issues.root_id IN (1,2)')
    end

    it 'handles empty ids for equality' do
      expect(query.sql_for_root_id_field('root_id', '=', ['abc'])).to eq('1=0')
    end

    it 'matches null roots for !*' do
      expect(query.sql_for_root_id_field('root_id', '!*', [])).to eq('issues.root_id IS NULL')
    end
  end

  describe '#sql_for_root_tracker_id_field' do
    it 'includes issues whose root matches the tracker' do
      expect(query.sql_for_root_tracker_id_field('root_tracker_id', '=', ['1'])).to eq(
        '((issues.id = issues.root_id AND issues.tracker_id IN (1)) OR (issues.root_id IN (SELECT id FROM issues WHERE tracker_id IN (1))))'
      )
    end

    it 'excludes issues whose root matches the tracker' do
      expect(query.sql_for_root_tracker_id_field('root_tracker_id', '!', ['1'])).to eq(
        'NOT ((issues.id = issues.root_id AND issues.tracker_id IN (1)) OR (issues.root_id IN (SELECT id FROM issues WHERE tracker_id IN (1))))'
      )
    end
  end

  describe '#sql_for_root_status_id_field' do
    it 'includes roots matching statuses' do
      expect(query.sql_for_root_status_id_field('root_status_id', '=', ['1'])).to eq(
        '((issues.id = issues.root_id AND issues.status_id IN (1)) OR (issues.root_id IN (SELECT id FROM issues WHERE status_id IN (1))))'
      )
    end

    it 'filters closed roots' do
      expect(query.sql_for_root_status_id_field('root_status_id', 'c', [])).to eq(
        '((issues.id = issues.root_id AND issues.status_id IN (SELECT id FROM issue_statuses WHERE is_closed = TRUE)) OR  (issues.root_id IN (SELECT id FROM issues WHERE status_id IN (SELECT id FROM issue_statuses WHERE is_closed = TRUE))))'
      )
    end

    it 'filters open roots' do
      expect(query.sql_for_root_status_id_field('root_status_id', 'o', [])).to eq(
        '((issues.id = issues.root_id AND issues.status_id IN (SELECT id FROM issue_statuses WHERE is_closed = FALSE)) OR (issues.root_id IN (SELECT id FROM issues WHERE status_id IN (SELECT id FROM issue_statuses WHERE is_closed = FALSE))))'
      )
    end
  end

  describe '#sql_for_parent_tracker_id_field' do
    it 'includes issues whose parent matches tracker' do
      expect(query.sql_for_parent_tracker_id_field('parent_tracker_id', '=', ['1'])).to eq(
        '(issues.parent_id IN (SELECT id FROM issues WHERE tracker_id IN (1)))'
      )
    end

    it 'excludes issues whose parent matches tracker' do
      expect(query.sql_for_parent_tracker_id_field('parent_tracker_id', '!', ['1'])).to eq(
        '(issues.parent_id NOT IN (SELECT id FROM issues WHERE tracker_id IN (1)) OR issues.parent_id IS NULL)'
      )
    end
  end

  describe '#sql_for_parent_status_id_field' do
    it 'includes parents with matching status' do
      expect(query.sql_for_parent_status_id_field('parent_status_id', '=', ['1'])).to eq(
        '(issues.parent_id IN (SELECT id FROM issues WHERE status_id IN (1)))'
      )
    end

    it 'matches open parent issues' do
      expect(query.sql_for_parent_status_id_field('parent_status_id', 'o', [])).to eq(
        '(issues.parent_id IN (SELECT id FROM issues WHERE status_id IN (SELECT id FROM issue_statuses WHERE is_closed = FALSE)))'
      )
    end

    it 'allows all parents when operator is *' do
      expect(query.sql_for_parent_status_id_field('parent_status_id', '*', [])).to be_nil
    end
  end

  describe '#sql_for_a_parent_tracker_id_field' do
    it 'returns descendants whose ancestors match tracker' do
      expect(query.sql_for_a_parent_tracker_id_field('a_parent_tracker_id', '=', ['1'])).to eq(
        '(issues.id IN (SELECT child.id FROM issues AS child WHERE EXISTS (SELECT 1  FROM issues AS ancestor  WHERE child.lft > ancestor.lft  AND child.rgt < ancestor.rgt  AND child.root_id = ancestor.root_id  AND ancestor.tracker_id IN (1))))'
      )
    end
  end

  describe '#sql_for_a_parent_status_id_field' do
    it 'returns descendants whose ancestors match open status' do
      expect(query.sql_for_a_parent_status_id_field('a_parent_status_id', 'o', [])).to eq(
        '(issues.id IN (SELECT child.id FROM issues AS child WHERE EXISTS (SELECT 1  FROM issues AS ancestor  WHERE child.lft > ancestor.lft  AND child.rgt < ancestor.rgt  AND child.root_id = ancestor.root_id  AND ancestor.status_id IN (SELECT id FROM issue_statuses WHERE is_closed = FALSE))))'
      )
    end
  end

  describe '#sql_for_a_specific_parent_tracker_id_field' do
    it 'builds a depth constrained tracker match' do
      expect(query.sql_for_a_specific_parent_tracker_id_field('a_specific_parent_tracker_id', '=', ['3:2'])).to eq(
        'issues.id IN (SELECT issues.id FROM issues INNER JOIN issues parent1 ON issues.parent_id = parent1.id INNER JOIN issues parent2 ON parent1.parent_id = parent2.id WHERE parent2.tracker_id IN (3))'
      )
    end
  end

  describe '#sql_for_a_specific_parent_status_id_field' do
    it 'builds a depth constrained status match' do
      expect(query.sql_for_a_specific_parent_status_id_field('a_specific_parent_status_id', '!', ['5:1'])).to eq(
        'issues.id NOT IN (SELECT issues.id FROM issues INNER JOIN issues parent1 ON issues.parent_id = parent1.id WHERE parent1.status_id IN (5))'
      )
    end
  end

  describe '#sql_for_child_tracker_id_field' do
    it 'includes issues with children matching tracker and status filters' do
      query.filters['child_status_id'] = { operator: '=', values: ['5'] }
      expect(query.sql_for_child_tracker_id_field('child_tracker_id', '=', ['3'])).to eq(
        '(issues.id IN (SELECT parent_id FROM issues WHERE tracker_id IN (3) AND status_id IN (5)))'
      )
    end
  end

  describe '#sql_for_child_status_id_field' do
    it 'excludes issues with children in the provided statuses' do
      expect(query.sql_for_child_status_id_field('child_status_id', '!', ['4'])).to eq(
        '(issues.id NOT IN (SELECT parent_id FROM issues WHERE status_id IN (4)) OR issues.parent_id IS NULL)'
      )
    end

    it 'matches open child statuses' do
      expect(query.sql_for_child_status_id_field('child_status_id', 'o', [])).to eq(
        '(issues.id IN (SELECT parent_id FROM issues WHERE status_id IN (SELECT id FROM issue_statuses WHERE is_closed=FALSE)))'
      )
    end
  end

  describe '#sql_for_tree_has_parent_or_child_field' do
    it 'returns root selection when requesting hierarchies' do
      expect(query.sql_for_tree_has_parent_or_child_field('tree_has_parent_or_child', '=', ['1']))
        .to eq('issues.root_id IN (SELECT DISTINCT scope.root_id FROM issues scope WHERE scope.parent_id IS NOT NULL OR EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = scope.id))')
    end

    it 'negates root selection when excluding hierarchies' do
      expect(query.sql_for_tree_has_parent_or_child_field('tree_has_parent_or_child', '=', ['0']))
        .to eq('issues.root_id NOT IN (SELECT DISTINCT scope.root_id FROM issues scope WHERE scope.parent_id IS NOT NULL OR EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = scope.id))')
    end
  end

  describe '#sql_for_tree_tracker_id_field' do
    it 'selects trees where any issue matches the tracker list' do
      expect(query.sql_for_tree_tracker_id_field('tree_tracker_id', '=', ['7'])).to eq(
        'issues.root_id IN (SELECT DISTINCT tree.root_id FROM issues tree WHERE tree.tracker_id IN (7))'
      )
    end

    it 'excludes trees when no issue matches the tracker list' do
      expect(query.sql_for_tree_tracker_id_field('tree_tracker_id', '!', ['8'])).to eq(
        'issues.root_id NOT IN (SELECT DISTINCT tree.root_id FROM issues tree WHERE tree.tracker_id IN (8))'
      )
    end
  end

  describe '#sql_for_tree_status_id_field' do
    it 'selects trees where any issue matches the status list' do
      expect(query.sql_for_tree_status_id_field('tree_status_id', '=', ['4'])).to eq(
        'issues.root_id IN (SELECT DISTINCT tree.root_id FROM issues tree WHERE tree.status_id IN (4))'
      )
    end

    it 'applies the operator to the entire tree' do
      expect(query.sql_for_tree_status_id_field('tree_status_id', '!', ['6'])).to eq(
        'issues.root_id NOT IN (SELECT DISTINCT tree.root_id FROM issues tree WHERE tree.status_id IN (6))'
      )
    end

    it 'filters by open statuses across the tree' do
      expect(query.sql_for_tree_status_id_field('tree_status_id', 'o', [])).to eq(
        'issues.root_id IN (SELECT DISTINCT tree.root_id FROM issues tree WHERE tree.status_id IN (SELECT id FROM issue_statuses WHERE is_closed=FALSE))'
      )
    end
  end

  describe '#tree_condition' do
    it 'includes root ids when positive equality is requested' do
      expect(query.send(:tree_condition, 'SELECT 1', '=', true)).to eq('issues.root_id IN (SELECT 1)')
    end

    it 'excludes root ids when negative equality is requested' do
      expect(query.send(:tree_condition, 'SELECT 1', '=', false)).to eq('issues.root_id NOT IN (SELECT 1)')
    end

    it 'negates for not-equal with positive flag' do
      expect(query.send(:tree_condition, 'SELECT 1', '!', true)).to eq('issues.root_id NOT IN (SELECT 1)')
    end

    it 'negates for not-equal with negative flag' do
      expect(query.send(:tree_condition, 'SELECT 1', '!', false)).to eq('issues.root_id IN (SELECT 1)')
    end
  end

  describe '#sql_for_tree_parent_tracker_id_field' do
    it 'builds tree selection for parent tracker matches' do
      expect(query.sql_for_tree_parent_tracker_id_field('tree_parent_tracker_id', '=', ['2'])).to eq(
        'issues.root_id IN (SELECT DISTINCT child.root_id FROM issues child INNER JOIN issues parent ON child.parent_id = parent.id WHERE parent.tracker_id IN (2) UNION SELECT DISTINCT issues.root_id FROM issues WHERE tracker_id IN (2) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = issues.id))'
      )
    end
  end

  describe '#sql_for_tree_parent_status_id_field' do
    it 'returns nil for all-status operator' do
      expect(query.sql_for_tree_parent_status_id_field('tree_parent_status_id', '*', ['1'])).to be_nil
    end

    it 'builds a subquery for matching parent statuses' do
      expect(query.sql_for_tree_parent_status_id_field('tree_parent_status_id', '=', ['1', '2']))
        .to eq('issues.root_id IN (SELECT DISTINCT child.root_id FROM issues child INNER JOIN issues parent ON child.parent_id = parent.id WHERE parent.status_id IN (1,2) UNION SELECT DISTINCT issues.root_id FROM issues WHERE status_id IN (1,2) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = issues.id))')
    end

    it 'uses closed condition when filtering closed parent statuses' do
      expect(query.sql_for_tree_parent_status_id_field('tree_parent_status_id', 'c', []))
        .to eq('issues.root_id IN (SELECT DISTINCT child.root_id FROM issues child INNER JOIN issues parent ON child.parent_id = parent.id WHERE parent.status_id IN (SELECT id FROM issue_statuses WHERE is_closed = TRUE) UNION SELECT DISTINCT issues.root_id FROM issues WHERE status_id IN (SELECT id FROM issue_statuses WHERE is_closed = TRUE) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = issues.id))')
    end
  end

  describe '#sql_for_tree_child_tracker_id_field' do
    it 'selects roots with matching child trackers and single matching issues' do
      expect(query.sql_for_tree_child_tracker_id_field('tree_child_tracker_id', '=', ['5']))
        .to eq('issues.root_id IN (SELECT DISTINCT parent.root_id FROM issues parent WHERE EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = parent.id AND child.tracker_id IN (5)) UNION SELECT DISTINCT issues.root_id FROM issues WHERE tracker_id IN (5) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = issues.id))')
    end
  end

  describe '#sql_for_tree_child_status_id_field' do
    it 'returns nil for all child statuses' do
      expect(query.sql_for_tree_child_status_id_field('tree_child_status_id', '*', ['1'])).to be_nil
    end

    it 'matches explicitly listed child statuses' do
      expect(query.sql_for_tree_child_status_id_field('tree_child_status_id', '=', ['3']))
        .to eq('issues.root_id IN (SELECT DISTINCT parent.root_id FROM issues parent WHERE EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = parent.id AND child.status_id IN (3)) UNION SELECT DISTINCT issues.root_id FROM issues WHERE status_id IN (3) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = issues.id))')
    end

    it 'matches open child statuses' do
      expect(query.sql_for_tree_child_status_id_field('tree_child_status_id', 'o', []))
        .to eq('issues.root_id IN (SELECT DISTINCT parent.root_id FROM issues parent WHERE EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = parent.id AND child.status_id IN (SELECT id FROM issue_statuses WHERE is_closed=FALSE)) UNION SELECT DISTINCT issues.root_id FROM issues WHERE status_id IN (SELECT id FROM issue_statuses WHERE is_closed=FALSE) AND parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM issues child WHERE child.parent_id = issues.id))')
    end
  end
end
