# frozen_string_literal: true

require_relative 'spec_helper'

# Redmine decides which issues a user may see; these filters decide which of them
# match. The two are separate concerns, and the hierarchy subqueries used to
# ignore the first one: they read the whole issues table, so a *visible* issue
# could be made to match, or not match, on the tracker, the status or the status
# history of a relative the user is not allowed to see.
#
# Nothing leaks directly — no id, subject or project of the hidden issue is ever
# returned. What leaks is an answer: "this issue has a closed Bug somewhere below
# it". Two queries differing only in a hidden relative must look identical to
# someone who cannot see that relative.
#
# Redmine core does apply Issue.visible_condition to a subtask subquery where it
# thought about it (the total_estimated_hours column), so scoping here follows
# core rather than inventing a policy.
RSpec.describe 'issues the user may not see' do
  # Sees public projects only, and within them only issues that are not private:
  # the built in "Non member" role has issues_visibility "default".
  let(:outsider) do
    user = User.new(:login => 'pcf_outsider', :firstname => 'Pcf', :lastname => 'Outsider',
                    :mail => 'pcf_outsider@example.net')
    user.password = 'pcf-secret-8712'
    user.save!
    user
  end

  let(:public_project)  { Project.find(1) } # eCookbook, is_public
  let(:private_project) { Project.find(2) } # OnlineStore, not public, outsider is no member }

  let(:tracker_visible) { Tracker.find(1) }
  let(:tracker_hidden)  { Tracker.find(2) }
  let(:status_visible)  { IssueStatus.find(1) }
  let(:status_hidden)   { IssueStatus.find(2) }

  before do
    # Needed only so a parent and a child can live in different projects at all.
    Setting.cross_project_subtasks = 'system'
  end

  def as_outsider
    previous = User.current
    User.current = outsider
    yield
  ensure
    User.current = previous
  end

  # Runs one filter as the outsider and returns the ids it matched.
  def matches(field, operator, values)
    as_outsider do
      query = unfiltered_query
      query.add_filter(field, operator, values)
      raise "invalid: #{query.errors.full_messages.join(', ')}" unless query.valid?

      query.issues.map(&:id)
    end
  end

  # --- the hidden relative is a child ---------------------------------------
  describe 'a hidden child' do
    let!(:visible_parent) do
      create_issue(:project => public_project, :tracker => tracker_visible, :status => status_visible)
    end

    shared_examples 'tells nothing about it' do
      it 'does not match the visible parent on the hidden child\'s tracker' do
        expect(matches('child_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_parent.id)
        expect(matches('a_child_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_parent.id)
      end

      it 'does not match the visible parent on the hidden child\'s status' do
        expect(matches('child_status_id', '=', [status_hidden.id.to_s])).not_to include(visible_parent.id)
        expect(matches('a_child_status_id', '=', [status_hidden.id.to_s])).not_to include(visible_parent.id)
      end

      it 'does not match through the tree filters either' do
        expect(matches('tree_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_parent.id)
        expect(matches('tree_child_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_parent.id)
        expect(matches('tree_child_status_id', '=', [status_hidden.id.to_s])).not_to include(visible_parent.id)
      end

      # "has no child with this tracker" is the honest answer for someone who
      # cannot see the child, and it is also the answer for an issue with no
      # children at all. Both must come out the same way.
      it 'answers the negation the way it answers it for a childless issue' do
        childless = create_issue(:project => public_project, :tracker => tracker_visible,
                                 :status => status_visible)

        negated = matches('child_tracker_id', '!', [tracker_hidden.id.to_s])
        expect(negated).to include(childless.id)
        expect(negated).to include(visible_parent.id)
      end

      it 'does not match on the hidden child\'s status history' do
        skip 'this Redmine has no history operators' unless history_operators?

        expect(matches('child_status_id', 'ev', [status_hidden.id.to_s])).not_to include(visible_parent.id)
      end
    end

    context 'in a project the user cannot see' do
      before do
        child = create_issue(:project => private_project, :tracker => tracker_hidden,
                             :status => status_hidden, :parent => visible_parent)
        # Give it a history entry so the "has been" operators have something to
        # find, then confirm the child really is invisible.
        child.init_journal(User.find(1))
        child.update!(:status => status_visible)
        child.reload.init_journal(User.find(1))
        child.update!(:status => status_hidden)

        expect(Issue.visible(outsider).where(:id => child.id)).to be_empty
        expect(Issue.visible(outsider).where(:id => visible_parent.id)).to be_present
      end

      include_examples 'tells nothing about it'
    end

    # A second, independent mechanism: same project, but the issue is private and
    # authored by someone else.
    context 'private, in a project the user can see' do
      before do
        child = create_issue(:project => public_project, :tracker => tracker_hidden,
                             :status => status_hidden, :parent => visible_parent)
        child.update_columns(:is_private => true)

        expect(Issue.visible(outsider).where(:id => child.id)).to be_empty
      end

      include_examples 'tells nothing about it'
    end
  end

  # --- the hidden relative is a parent, an ancestor or the root -------------
  describe 'a hidden parent' do
    let!(:hidden_parent) do
      create_issue(:project => private_project, :tracker => tracker_hidden, :status => status_hidden)
    end
    let!(:visible_child) do
      create_issue(:project => public_project, :tracker => tracker_visible,
                   :status => status_visible, :parent => hidden_parent)
    end

    before do
      expect(Issue.visible(outsider).where(:id => hidden_parent.id)).to be_empty
      expect(Issue.visible(outsider).where(:id => visible_child.id)).to be_present
    end

    it 'does not match the visible child on the hidden parent\'s tracker' do
      expect(matches('parent_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_child.id)
      expect(matches('a_parent_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_child.id)
    end

    it 'does not match the visible child on the hidden parent\'s status' do
      expect(matches('parent_status_id', '=', [status_hidden.id.to_s])).not_to include(visible_child.id)
      expect(matches('a_parent_status_id', '=', [status_hidden.id.to_s])).not_to include(visible_child.id)
    end

    it 'does not match on a hidden ancestor at a named level' do
      expect(matches('a_specific_parent_tracker_id', '=', ["#{tracker_hidden.id}:1"]))
        .not_to include(visible_child.id)
      expect(matches('a_specific_parent_status_id', '=', ["#{status_hidden.id}:1"]))
        .not_to include(visible_child.id)
    end

    it 'does not match on the hidden root' do
      expect(matches('root_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_child.id)
      expect(matches('root_status_id', '=', [status_hidden.id.to_s])).not_to include(visible_child.id)
    end

    it 'does not match through the tree filters' do
      expect(matches('tree_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_child.id)
      expect(matches('tree_parent_tracker_id', '=', [tracker_hidden.id.to_s])).not_to include(visible_child.id)
      expect(matches('tree_parent_status_id', '=', [status_hidden.id.to_s])).not_to include(visible_child.id)
    end
  end

  # Scoping the subqueries must not cost the ordinary case anything: a user who
  # can see both ends still gets the match.
  describe 'a user who can see everything' do
    let!(:parent) do
      create_issue(:project => public_project, :tracker => tracker_visible, :status => status_visible)
    end
    let!(:child) do
      create_issue(:project => public_project, :tracker => tracker_hidden,
                   :status => status_hidden, :parent => parent)
    end

    it 'still matches on the child' do
      expect(issue_ids_for('child_tracker_id' => ['=', [tracker_hidden.id.to_s]])).to include(parent.id)
      expect(issue_ids_for('child_status_id' => ['=', [status_hidden.id.to_s]])).to include(parent.id)
    end

    it 'still matches on the parent' do
      expect(issue_ids_for('parent_tracker_id' => ['=', [tracker_visible.id.to_s]])).to include(child.id)
      expect(issue_ids_for('root_tracker_id' => ['=', [tracker_visible.id.to_s]])).to include(child.id)
    end
  end

  # --- the structural filters -----------------------------------------------
  #
  # The filters above ask about a relative's tracker, status or history. These ask
  # only whether a relative exists, which makes them the sharpest form of the same
  # oracle: the answer is exactly one bit about an issue the user may not see.
  #
  # Four subqueries used to read the issues table here without scoping it, while the
  # eight others scoped theirs — so "has a child" meant "has a child in the
  # database" rather than "has a child you can see", and an issue whose only child
  # was hidden was not standalone.
  #
  # The assertion is indistinguishability, not "does not match". Which side of the
  # filter an issue lands on is a product question; that a hidden relative decides it
  # is a security question. Two issues differing only in a hidden relative have to
  # land on the same side, whichever side that turns out to be.
  describe 'the structural filters' do
    # The twin the outsider is allowed to reason about, in both worlds.
    let!(:twin_alone) do
      create_issue(:project => public_project, :tracker => tracker_visible, :status => status_visible)
    end

    def expect_indistinguishable(subject, field, operator, values)
      matched = matches(field, operator, values)
      with    = matched.include?(subject.id)
      without = matched.include?(twin_alone.id)

      expect(with).to eq(without),
                      "#{field} #{operator} #{values.inspect} told the two apart: the issue with a " \
                      "hidden relative was #{with ? 'matched' : 'not matched'} while the one without " \
                      "it was #{without ? 'matched' : 'not matched'}"
    end

    context 'when the hidden relative is a child' do
      let!(:twin_with_hidden_child) do
        create_issue(:project => public_project, :tracker => tracker_visible, :status => status_visible)
      end

      before do
        hidden = create_issue(:project => private_project, :tracker => tracker_hidden,
                              :status => status_hidden, :parent => twin_with_hidden_child)

        expect(Issue.visible(outsider).where(:id => hidden.id)).to be_empty
        expect(Issue.visible(outsider).where(:id => twin_with_hidden_child.id)).to be_present
        expect(Issue.visible(outsider).where(:id => twin_alone.id)).to be_present
      end

      it 'cannot tell a hidden child from no child at all' do
        %w[= !].each do |operator|
          %w[1 0].each do |flag|
            expect_indistinguishable(twin_with_hidden_child, 'tree_has_parent_or_child', operator, [flag])
          end
        end
      end

      it 'cannot tell it through any/none either' do
        %w[* !*].each do |operator|
          expect_indistinguishable(twin_with_hidden_child, 'tree_has_parent_or_child', operator, [''])
        end
      end

      # The one that bites: before the fix the hidden child stopped this issue from
      # being standalone, so it dropped out of a filter its twin matched.
      it 'still counts as standalone for the tree child filters' do
        expect_indistinguishable(twin_with_hidden_child, 'tree_child_tracker_id', '=',
                                 [tracker_visible.id.to_s])
        expect_indistinguishable(twin_with_hidden_child, 'tree_child_status_id', '=',
                                 [status_visible.id.to_s])
      end

      it 'still counts as standalone for the tree parent filters' do
        expect_indistinguishable(twin_with_hidden_child, 'tree_parent_tracker_id', '=',
                                 [tracker_visible.id.to_s])
        expect_indistinguishable(twin_with_hidden_child, 'tree_parent_status_id', '=',
                                 [status_visible.id.to_s])
      end
    end

    context 'when the hidden relative is a parent' do
      let!(:twin_with_hidden_parent) do
        parent = create_issue(:project => private_project, :tracker => tracker_hidden,
                              :status => status_hidden)
        create_issue(:project => public_project, :tracker => tracker_visible,
                     :status => status_visible, :parent => parent)
      end

      before do
        expect(Issue.visible(outsider).where(:id => twin_with_hidden_parent.parent_id)).to be_empty
        expect(Issue.visible(outsider).where(:id => twin_with_hidden_parent.id)).to be_present
      end

      it 'cannot tell a hidden parent from no parent at all' do
        %w[= !].each do |operator|
          %w[1 0].each do |flag|
            expect_indistinguishable(twin_with_hidden_parent, 'tree_has_parent_or_child', operator, [flag])
          end
        end
      end

      it 'still counts as standalone for the tree filters' do
        expect_indistinguishable(twin_with_hidden_parent, 'tree_parent_tracker_id', '=',
                                 [tracker_visible.id.to_s])
        expect_indistinguishable(twin_with_hidden_parent, 'tree_child_tracker_id', '=',
                                 [tracker_visible.id.to_s])
      end
    end

    # The operator matrix, crossed with visibility.
    #
    # The gap that made this necessary: the examples above test every operator on
    # tree_has_parent_or_child but only the value operator on the four tree
    # parent/child families, so "any" and "none" on those four went through an
    # existence subquery nothing exercised — and it still read parent_id IS NOT NULL
    # without asking whether that parent is visible. A green suite is no evidence
    # about an operator nobody ran. So the operators are crossed with the filters
    # rather than sampled per filter.
    PCF_LINKED_FAMILIES = %w[
      tree_parent_tracker_id tree_parent_status_id
      tree_child_tracker_id tree_child_status_id
    ].freeze

    %w[* !*].each do |operator|
      PCF_LINKED_FAMILIES.each do |field|
        it "tells nothing about a hidden child through #{field} #{operator}" do
          twin = create_issue(:project => public_project, :tracker => tracker_visible,
                              :status => status_visible)
          hidden = create_issue(:project => private_project, :tracker => tracker_hidden,
                                :status => status_hidden, :parent => twin)
          expect(Issue.visible(outsider).where(:id => hidden.id)).to be_empty

          expect_indistinguishable(twin, field, operator, [''])
        end

        it "tells nothing about a hidden parent through #{field} #{operator}" do
          hidden = create_issue(:project => private_project, :tracker => tracker_hidden,
                                :status => status_hidden)
          twin = create_issue(:project => public_project, :tracker => tracker_visible,
                              :status => status_visible, :parent => hidden)
          expect(Issue.visible(outsider).where(:id => hidden.id)).to be_empty
          expect(Issue.visible(outsider).where(:id => twin.id)).to be_present

          expect_indistinguishable(twin, field, operator, [''])
        end
      end
    end

    # ...and the other half of the contract: a relationship both of whose ends are
    # visible must still be reported, or the filters would be trivially "safe" by
    # answering nothing.
    PCF_LINKED_FAMILIES.each do |field|
      it "still reports a relationship it can see through #{field}" do
        parent = create_issue(:project => public_project, :tracker => tracker_visible,
                              :status => status_visible)
        create_issue(:project => public_project, :tracker => tracker_visible,
                     :status => status_visible, :parent => parent)

        linked = matches(field, '*', [''])
        expect(linked).to include(parent.id)
        expect(linked).not_to include(twin_alone.id)

        unlinked = matches(field, '!*', [''])
        expect(unlinked).to include(twin_alone.id)
        expect(unlinked).not_to include(parent.id)
      end
    end

    # The scoping must not cost the ordinary case anything: relatives you can see
    # still count as relatives.
    context 'when both ends are visible' do
      let!(:visible_parent) do
        create_issue(:project => public_project, :tracker => tracker_visible, :status => status_visible)
      end

      before do
        create_issue(:project => public_project, :tracker => tracker_visible,
                     :status => status_visible, :parent => visible_parent)
      end

      it 'reports the relationship it can see' do
        linked = matches('tree_has_parent_or_child', '=', ['1'])

        expect(linked).to include(visible_parent.id)
        expect(linked).not_to include(twin_alone.id)
      end
    end
  end
end
