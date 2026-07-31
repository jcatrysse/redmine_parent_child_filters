# frozen_string_literal: true

require_relative 'spec_helper'

# Which text counts as a mention. The existing mention_filter_spec covers the
# filter; this covers the matching itself, across the things a text search gets
# wrong: case, the characters Redmine allows in a login, line endings, letters
# from other scripts next to the boundary, and accounts that no longer work.
#
# Redmine's own MENTION_PATTERN carries the /i flag and logins are unique case
# insensitively, so @JSmith and @jsmith are the same person. PostgreSQL says that
# in the operator (~*); MySQL's REGEXP follows the column collation instead, so
# the pattern says it with an inline (?i).
RSpec.describe 'what counts as a mention' do
  let(:project) { Project.find(1) }

  def user_with_login(login)
    user = User.new(:firstname => 'Men', :lastname => 'Tion',
                    :mail => "#{login.gsub(/[^a-z0-9]/i, '')}@example.net")
    user.login = login
    user.save!(:validate => false)
    user
  end

  def issue_saying(text, in_notes: false)
    issue = Issue.new(:project => project, :tracker => project.trackers.first,
                      :status => IssueStatus.sorted.first, :author => User.find(1),
                      :subject => 'mention matching', :priority => IssuePriority.active.first,
                      :description => in_notes ? 'nothing here' : text)
    issue.save!

    if in_notes
      issue = Issue.find(issue.id)
      issue.init_journal(User.find(1), text)
      issue.save!
    end
    Issue.find(issue.id)
  end

  def mentions?(user, text, in_notes: false)
    issue = issue_saying(text, :in_notes => in_notes)
    issue_ids_for('mentioned_id' => ['=', [user.id.to_s]]).include?(issue.id)
  end

  describe 'case' do
    let(:user) { user_with_login('jsmith2') }

    # Both places the filter looks, because the description and the notes are
    # different columns and could carry different collations on MySQL.
    [false, true].each do |in_notes|
      where = in_notes ? 'a note' : 'the description'

      it "matches a mention written in another case, in #{where}" do
        expect(mentions?(user, 'ping @JSmith2 please', :in_notes => in_notes)).to be true
        expect(mentions?(user, 'ping @JSMITH2 please', :in_notes => in_notes)).to be true
        expect(mentions?(user, 'ping @jsmith2 please', :in_notes => in_notes)).to be true
      end
    end

    it 'matches a mention of a login that has capitals itself' do
      capitalised = user_with_login('JSmith3')

      expect(mentions?(capitalised, 'ping @jsmith3 please')).to be true
      expect(mentions?(capitalised, 'ping @JSmith3 please')).to be true
    end
  end

  # Redmine validates logins against /\A[a-z0-9_\-@\.]*\z/i, so every one of
  # these is a login somebody can have, and every one of . - _ @ is either a
  # regular expression metacharacter or a boundary character in the pattern.
  describe 'the characters a login may contain' do
    {
      'plain' => 'abc123',
      'underscore' => 'a_b',
      'hyphen' => 'a-b',
      'dot' => 'a.b',
      'at sign' => 'a@b',
      'all at once' => 'a_b-c.d@e',
      'leading digit' => '1abc',
      'single letter' => 'q'
    }.each do |name, login|
      it "matches a login with #{name} (#{login})" do
        user = user_with_login(login)

        expect(mentions?(user, "hello @#{login} bye")).to be true
      end

      it "does not match #{name} (#{login}) when more login characters follow" do
        user = user_with_login(login)

        expect(mentions?(user, "hello @#{login}x bye")).to be false
      end
    end
  end

  describe 'where the mention sits' do
    let(:user) { user_with_login('edge1') }

    {
      'at the very start' => '@edge1 look',
      'at the very end' => 'look @edge1',
      'alone' => '@edge1',
      'before a comma' => 'ask @edge1, please',
      'before a full stop' => 'ask @edge1.',
      'in brackets' => 'ask (@edge1) please',
      'after a newline' => "line one\n@edge1 look",
      'before a newline' => "@edge1\nline two",
      'after a CRLF' => "line one\r\n@edge1 look",
      'before a CRLF' => "@edge1\r\nline two",
      'between tabs' => "\t@edge1\t",
      'twice' => '@edge1 and @edge1'
    }.each do |name, text|
      it "matches #{name}" do
        expect(mentions?(user, text)).to be true
      end
    end

    {
      'as part of a longer login' => '@edge1x',
      'as part of an address' => 'mail someone@edge1.example',
      'without the at sign' => 'edge1 said so',
      'preceded by a login char' => 'x@edge1'
    }.each do |name, text|
      it "does not match #{name}" do
        expect(mentions?(user, text)).to be false
      end
    end

    # A documented difference from Redmine's notifications rather than a bug: the
    # boundary is "a character a login may not contain", so a letter from another
    # script ends the mention. Redmine's own pattern requires punctuation, space
    # or end of text there and so would not notify. Pinned so the difference is a
    # decision rather than a surprise.
    it 'treats a letter from another script as a boundary, unlike core' do
      user = user_with_login('edge2')

      expect(mentions?(user, 'ping @edge2é')).to be true
      expect(Redmine::Acts::Mentionable::InstanceMethods::MENTION_PATTERN)
        .to be_a(Regexp) # the pattern this differs from still exists
    end
  end

  describe 'accounts that cannot be mentioned usefully' do
    it 'still matches a locked user, because the text still names them' do
      user = user_with_login('locked1')
      user.update_columns(:status => User::STATUS_LOCKED)

      expect(mentions?(user, 'ping @locked1')).to be true
    end

    it 'matches a registered but unactivated user' do
      user = user_with_login('pending1')
      user.update_columns(:status => User::STATUS_REGISTERED)

      expect(mentions?(user, 'ping @pending1')).to be true
    end

    # The filter resolves ids to logins, so an id that no longer exists resolves
    # to nothing and the filter matches nothing rather than raising.
    it 'matches nothing for a user that no longer exists' do
      user = user_with_login('gone1')
      issue = issue_saying('ping @gone1')
      id = user.id
      user.delete

      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [id.to_s])

      expect { query.issue_count }.not_to raise_error
      expect(query.issues.map(&:id)).not_to include(issue.id)
    end

    # No login means no @login to look for, but user#<id> still names them, so the
    # filter has something to do rather than nothing. Before the link form was
    # matched this produced 1=0.
    it 'can still find a user without a login, by id' do
      user = user_with_login('nologin1')
      user.update_columns(:login => '')
      issue = issue_saying("see user##{user.id} about this")

      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [user.id.to_s])

      expect(query.statement).not_to include('1=0')
      expect(query.issues.map(&:id)).to include(issue.id)
    end
  end

  # Redmine has a second way of pointing at a person: user#176, which
  # application_helper renders as a link to that profile. It notifies nobody —
  # MENTION_PATTERN does not know it — but people write it meaning the same thing, so
  # this filter matches it. The bounds come from Redmine's own LINKS_RE.
  describe 'the user#<id> link form' do
    let(:user) { user_with_login('linkform1') }
    let(:other) { user_with_login('linkform2') }

    it 'matches a link in the description' do
      expect(mentions?(user, "please review, see user##{user.id}")).to be true
    end

    it 'matches a link in a note' do
      expect(mentions?(user, "handing this to user##{user.id}", :in_notes => true)).to be true
    end

    it 'matches the double hash form Redmine also renders' do
      expect(mentions?(user, "see user###{user.id} for context")).to be true
    end

    it 'matches at the very start of the text' do
      expect(mentions?(user, "user##{user.id} asked for this")).to be true
    end

    it 'matches when a sentence ends right after it' do
      expect(mentions?(user, "assigned to user##{user.id}.")).to be true
    end

    # The boundary cases, which are the whole reason this is a regular expression and
    # not a LIKE.
    it 'does not match an id that merely starts with this one' do
      expect(mentions?(user, "see user##{user.id}0 about this")).to be false
    end

    it 'does not match when a letter follows the id' do
      expect(mentions?(user, "see user##{user.id}x about this")).to be false
    end

    it 'does not match inside a longer word' do
      expect(mentions?(user, "ask the superuser##{user.id} instead")).to be false
    end

    # Redmine's own escape: a leading "!" tells the formatter to print the text and
    # render no link. It falls out of using LINKS_RE's lead set, since "!" is not in it,
    # but it falls out by accident unless something says so.
    it 'does not match the escaped form Redmine refuses to link' do
      expect(mentions?(user, "write !user##{user.id} to show it literally")).to be false
    end

    it 'does not match another user\'s id' do
      expect(mentions?(other, "see user##{user.id} about this")).to be false
    end

    it 'still matches the @login form alongside it' do
      expect(mentions?(user, 'ping @linkform1 please')).to be true
    end

    it 'matches either form when both people are selected' do
      by_login = issue_saying('ping @linkform1')
      by_link = issue_saying("see user##{other.id}")

      found = issue_ids_for('mentioned_id' => ['=', [user.id.to_s, other.id.to_s]])

      expect(found).to include(by_login.id, by_link.id)
    end

    # Documented divergence: LINKS_RE has no /i, so Redmine does not link this, but the
    # pattern is case insensitive as a whole because the login half must be.
    it 'also matches a shouted prefix, unlike core' do
      expect(mentions?(user, "see USER##{user.id} about this")).to be true
    end

    it 'reaches the combined filter too' do
      issue = issue_saying("see user##{user.id}")

      expect(issue_ids_for('involved_or_mentioned_id' => ['=', [user.id.to_s]]))
        .to include(issue.id)
    end

    # The prefilter has to stay a prefilter: anything the expression accepts must
    # satisfy one of the LIKEs, or rows would be dropped before the expression sees
    # them.
    it 'keeps the prefilter wide enough for both forms' do
      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [user.id.to_s])
      statement = query.statement

      expect(statement).to include('%@%')
      expect(statement).to include('%user#%')
    end
  end

  # Groups have no login, so they cannot be mentioned. In the combined filter
  # they must still work through the involvement half.
  describe 'a group in the combined filter' do
    let!(:group) do
      group = Group.new(:name => 'Pcf Mention Group')
      group.save!
      group
    end

    before do
      Setting.issue_group_assignment = '1'
      Member.create!(:project => project, :principal => group,
                     :roles => [Role.find_by(:name => 'Manager') || Role.first])
    end

    it 'matches on assignment, not on the text' do
      assigned = Issue.new(:project => project, :tracker => project.trackers.first,
                           :status => IssueStatus.sorted.first, :author => User.find(1),
                           :subject => 'group assigned', :assigned_to => group,
                           :priority => IssuePriority.active.first)
      assigned.save!
      mentioned = issue_saying("ping @#{group.name}")

      ids = issue_ids_for('involved_or_mentioned_id' => ['=', [group.id.to_s]])
      expect(ids).to include(assigned.id)
      expect(ids).not_to include(mentioned.id)
    end

    it 'matches nothing at all for the mention only filter' do
      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [group.id.to_s])

      expect(query.statement).to include('1=0')
    end
  end

  # The filter exists to find the issues Redmine notified you about, so the
  # question that matters is not "does the regular expression work" but "does it
  # agree with the pattern that sent the notification". This runs a corpus through
  # both and requires them to agree, except where they are known not to.
  #
  # A future Redmine changing MENTION_PATTERN will land here rather than in a bug
  # report.
  describe 'against Redmine\'s own notification pattern' do
    LOGIN = 'corpus1'

    CORPUS = [
      '@corpus1', 'ping @corpus1', 'ping @corpus1 x', 'ping @corpus1.',
      'ping @corpus1..', 'ping @corpus1...', 'ping @corpus1,', 'ping @corpus1!',
      'ping @corpus1?', 'ping @corpus1;', 'ping @corpus1:', 'ping @corpus1)',
      '(@corpus1)', 'ping @corpus1-', 'ping @corpus1@', 'ping @corpus1/',
      'ping @corpus1"', "@corpus1\n", "@corpus1\r\n", "\t@corpus1\t",
      'ping @corpus1, ok', 'ping @corpus1. ok', '@corpus1x', 'ping @corpus1x',
      'ping @corpus1.example', 'someone@corpus1.example', 'x@corpus1',
      'ping -@corpus1', 'ping .@corpus1', 'ping @@corpus1',
      'see @corpus1/@other', 'ping @Corpus1', 'PING @CORPUS1.', 'a-b@corpus1',
      'ping corpus1', 'ping @corpus11', 'ping @corpus1-x'
    ].freeze

    # Where the filter deliberately differs from core, with the reason. Kept as
    # data so the list can only shrink by accident, never grow by accident.
    KNOWN_DIVERGENCES = {
      'ping @corpus1é' =>
        'the boundary is "a character no login may contain", so a letter from ' \
        'another script ends the mention; core requires punctuation, space or end',
      'ping @corpus1_' =>
        'core treats _ as punctuation and notifies, although _ is legal in a ' \
        'login, so the text reads as the login corpus1_',
      'ping @corpus1.@x' =>
        'core notifies corpus1; the text reads as the login corpus1.@x'
    }.freeze

    let!(:user) { user_with_login(LOGIN) }

    def core_notifies?(text)
      pattern = Redmine::Acts::Mentionable::InstanceMethods::MENTION_PATTERN
      # Redmine resolves the captured logins case insensitively, as logins are
      # unique that way.
      text.scan(pattern).flatten.map(&:downcase).include?(LOGIN)
    end

    (CORPUS + KNOWN_DIVERGENCES.keys).each do |text|
      it "agrees with core on #{text.inspect}" do
        expected = core_notifies?(text)
        actual = mentions?(user, text)

        if (reason = KNOWN_DIVERGENCES[text])
          expect(actual).not_to eq(expected), "#{text.inspect} no longer diverges: #{reason}"
        else
          expect(actual).to eq(expected),
                            "#{text.inspect}: core notifies #{expected}, the filter says #{actual}"
        end
      end
    end

    it 'diverges on three texts and no more' do
      diverging = (CORPUS + KNOWN_DIVERGENCES.keys).reject do |text|
        mentions?(user, text) == core_notifies?(text)
      end

      expect(diverging.sort).to eq(KNOWN_DIVERGENCES.keys.sort)
    end
  end

  # The pattern must not depend on the column's collation on MySQL, which is what
  # would make the same text match on one instance and not on another.
  describe 'the SQL it builds' do
    it 'states case insensitivity in the pattern on MySQL' do
      skip 'MySQL only' unless Redmine::Database.mysql?

      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [user_with_login('sqlshape1').id.to_s])

      expect(query.statement).to include('REGEXP')
      expect(query.statement).to include('(?i)')
    end

    it 'uses the case insensitive operator on PostgreSQL' do
      skip 'PostgreSQL only' unless Redmine::Database.postgresql?

      query = unfiltered_query
      query.add_filter('mentioned_id', '=', [user_with_login('sqlshape2').id.to_s])

      expect(query.statement).to include('~*')
    end

    # The regression itself, at the level where it happens. A binary collation is
    # what an instance ends up with after a migration from an older MySQL, and the
    # suite's own tables use the default one, so the collation has to be forced
    # here or this would pass either way.
    it 'matches under a binary collation on MySQL' do
      skip 'MySQL only' unless Redmine::Database.mysql?

      column = "(_utf8mb4'ping @Collate1 now' COLLATE utf8mb4_bin)"
      condition = unfiltered_query.send(:pcf_mention_regexp, column, ['collate1'], [])

      expect(ActiveRecord::Base.connection.select_value("SELECT #{condition}").to_i).to eq(1)
    end
  end
end
