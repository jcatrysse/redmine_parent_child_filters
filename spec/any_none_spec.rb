# frozen_string_literal: true

require_relative 'spec_helper'

# The "any" and "none" operators, which Redmine offers on every list filter and
# which this plugin never gave a meaning to. They used to answer three different
# ways depending on the filter, none of them right, and "any" and "none" gave the
# same answer everywhere — so the interface offered a choice that made no
# difference.
#
# The rule now follows the one already documented for "is not": a filter that
# ranges over a set of relatives asks about the existence of one.
#
#   any  -> there is such a relative
#   none -> there is none
#
# For the root and whole-tree filters the set is never empty, because every issue
# has a root and belongs to a tree. There "any" is every issue and "none" is no
# issue, which is what the root filter already did.
RSpec.describe 'any and none' do
  let(:project) { Project.find(1) }

  let!(:parent)     { create_issue(:project => project) }
  let!(:child)      { create_issue(:project => project, :parent => parent) }
  let!(:standalone) { create_issue(:project => project) }

  # Fixture issues have relatives of their own, so the assertions are about the
  # three issues above rather than about exact result sets.
  def matched(field, operator)
    ids = issue_ids_for(field => [operator, ['']])
    {:parent => ids.include?(parent.id), :child => ids.include?(child.id),
     :standalone => ids.include?(standalone.id), :count => ids.size}
  end

  def all_issues
    all_visible_issue_ids.size
  end

  # [filters, what "any" means]
  HAS_A_PARENT = %w[
    parent_tracker_id parent_status_id
    a_parent_tracker_id a_parent_status_id
    a_specific_parent_tracker_id a_specific_parent_status_id
  ].freeze

  HAS_A_CHILD = %w[
    child_tracker_id child_status_id a_child_tracker_id a_child_status_id
  ].freeze

  IN_A_TREE_WITH_A_LINK = %w[
    tree_parent_tracker_id tree_parent_status_id
    tree_child_tracker_id tree_child_status_id
  ].freeze

  ALWAYS_TRUE = %w[
    root_id root_tracker_id root_status_id
    tree_tracker_id tree_status_id tree_has_parent_or_child
  ].freeze

  HAS_A_PARENT.each do |field|
    describe field do
      it 'any means the issue has a parent' do
        expect(matched(field, '*')).to include(:parent => false, :child => true,
                                               :standalone => false)
      end

      it 'none means it has no parent' do
        expect(matched(field, '!*')).to include(:parent => true, :child => false,
                                                :standalone => true)
      end
    end
  end

  HAS_A_CHILD.each do |field|
    describe field do
      it 'any means the issue has a child' do
        expect(matched(field, '*')).to include(:parent => true, :child => false,
                                               :standalone => false)
      end

      it 'none means it has none' do
        expect(matched(field, '!*')).to include(:parent => false, :child => true,
                                                :standalone => true)
      end
    end
  end

  IN_A_TREE_WITH_A_LINK.each do |field|
    describe field do
      it 'any means the issue is in a tree that has a parent and a child' do
        expect(matched(field, '*')).to include(:parent => true, :child => true,
                                               :standalone => false)
      end

      it 'none means it is in a tree that has neither' do
        expect(matched(field, '!*')).to include(:parent => false, :child => false,
                                                :standalone => true)
      end
    end
  end

  ALWAYS_TRUE.each do |field|
    describe field do
      it 'any is every issue, because every issue has a root and a tree' do
        expect(matched(field, '*')[:count]).to eq(all_issues)
      end

      it 'none is no issue' do
        expect(matched(field, '!*')[:count]).to eq(0)
      end
    end
  end

  # The property that was broken across the whole filter set: the interface offers
  # both, so they must not answer the same way.
  it 'answers differently for any than for none, on every filter' do
    same = (HAS_A_PARENT + HAS_A_CHILD + IN_A_TREE_WITH_A_LINK + ALWAYS_TRUE).select do |field|
      issue_ids_for(field => ['*', ['']]) == issue_ids_for(field => ['!*', ['']])
    end

    expect(same).to eq([])
  end

  # Together they must cover everything and overlap in nothing: an issue either
  # has such a relative or it does not.
  it 'partitions the issues, on every filter' do
    (HAS_A_PARENT + HAS_A_CHILD + IN_A_TREE_WITH_A_LINK + ALWAYS_TRUE).each do |field|
      any = issue_ids_for(field => ['*', ['']])
      none = issue_ids_for(field => ['!*', ['']])

      expect(any & none).to eq([]), "#{field}: an issue is in both any and none"
      expect((any | none).sort).to eq(all_visible_issue_ids), "#{field}: some issue is in neither"
    end
  end

  it 'never produces a nil condition, which Redmine turns into no filter at all' do
    nils = []

    (HAS_A_PARENT + HAS_A_CHILD + IN_A_TREE_WITH_A_LINK + ALWAYS_TRUE).each do |field|
      %w[* !*].each do |operator|
        query = unfiltered_query
        query.add_filter(field, operator, [''])
        nils << "#{field} #{operator}" if query.statement.nil? || query.statement.empty?
      end
    end

    expect(nils).to eq([])
  end
end
