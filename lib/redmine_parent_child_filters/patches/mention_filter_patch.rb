# frozen_string_literal: true

require_dependency 'issue_query'
require File.expand_path('filter_registration', __dir__)
require File.expand_path('principal_filter_support', __dir__)

# Redmine records mentions but does not store them: Redmine::Acts::Mentionable
# scans the text on save, notifies the users it finds and throws the result
# away. There is no mentions table on any Redmine from 5.0 to 7.0, so the filter
# has to look at the text itself.
#
# Matching happens in two stages. A LIKE per login narrows the rows down
# cheaply, then a single regular expression applies the word boundary that LIKE
# cannot express, so that "@jan" does not match "@jansen" or an address like
# "someone@jan.example". The regular expression is authoritative and the LIKE is
# only a prefilter: a text that satisfies the expression always satisfies the
# corresponding LIKE, so the two together select exactly what the expression
# alone would, for less work.
module RedmineParentChildFilters
  module Patches
    module MentionFilterPatch
      module InstanceMethods
        include PrincipalFilterSupport

        # What may sit around a mention. The three pieces are separate because the
        # rules genuinely differ, and collapsing them into one character class is
        # what made the filter disagree with Redmine's own notifications.
        #
        # Measured against Redmine's MENTION_PATTERN over a corpus of 40 texts,
        # these three leave three disagreements, all rare and all documented in
        # the readme. One character class left ten, including "@jsmith." — the
        # ordinary way to end a sentence.

        # Before the @: anything a login cannot start after. Redmine uses \W here,
        # which allows a dot or a hyphen, so "see -@jsmith" is a mention. The @
        # itself is excluded, or "@@jsmith" would read as a mention of jsmith
        # rather than of the login "@jsmith".
        MENTION_LEAD = '[^A-Za-z0-9_@]'

        # Straight after the login: punctuation that is legal in a login but is
        # usually sentence punctuation. "@jsmith." and "@jsmith..." are mentions;
        # "@jsmith.example" is a mention of the login jsmith.example, which is why
        # this may only be followed by a boundary.
        MENTION_TRAILING_PUNCT = '[.@-]*'

        # After that: a character no login may contain, or the end of the text.
        MENTION_BOUNDARY = '[^A-Za-z0-9_@.-]'

        # Redmine's other way of pointing at a person: user#176, which
        # application_helper renders as a link to that user's profile. It is not a
        # mention — MENTION_PATTERN does not know it and nobody is notified — but
        # people write it meaning the same thing, so this filter matches it too. See
        # the readme for what that makes the filter mean.
        #
        # Both bounds are taken from Redmine's LINKS_RE rather than invented. Before
        # "user" it allows only whitespace, "(", ",", "-", "[" or ">", so "superuser#176"
        # is not a link and neither is ".user#176". After the id a letter, digit or
        # underscore ends the match: "user#1760" is a different user and "user#176x" is
        # not a link at all — the same class of mistake as "@jan" matching "@jansen".
        #
        # One deliberate divergence: LINKS_RE carries no /i, so "USER#176" is not a link
        # to Redmine, while this pattern is case insensitive as a whole because the
        # login half has to be. A shouted reference is still a reference, so the false
        # positive is accepted rather than split into two patterns.
        LINK_LEAD = '[\s(,\[>-]'
        LINK_BOUNDARY = '[^A-Za-z0-9_]'

        def initialize_available_filters
          super

          pcf_register_filter('mentioned_id',
                              :type => :list,
                              :values => lambda { pcf_principal_values(:users_only => true) })
          pcf_register_filter('involved_or_mentioned_id',
                              :type => :list, :values => lambda { pcf_principal_values })
        end

        def sql_for_mentioned_id_field(field, operator, value)
          condition = pcf_mention_condition(pcf_principal_ids(value))
          return pcf_no_principal_condition(operator) if condition.nil?

          operator == '!' ? "NOT (#{condition})" : "(#{condition})"
        end

        # Everything involved_id covers, plus being mentioned in the description
        # or in a note the current user is allowed to read.
        def sql_for_involved_or_mentioned_id_field(field, operator, value)
          ids = pcf_principal_ids(value)
          legs = ids.empty? ? [] : pcf_involvement_legs(ids)
          mention = pcf_mention_condition(ids)
          legs << mention if mention
          return pcf_no_principal_condition(operator) if legs.empty?

          condition = "(#{legs.join(' OR ')})"
          operator == '!' ? "NOT #{condition}" : condition
        end

        private

        # The selected principals resolved to what the text may name them by: a login
        # for @login, an id for user#<id>. Groups have neither and simply drop out.
        # Memoised: Redmine builds the statement several times per request, for the
        # count, the page and any total.
        #
        # One query for both, so the two forms cannot end up describing different
        # people. A login may be blank on an account created before Redmine required
        # one, and such a user is still reachable by id, so the two lists are filtered
        # separately rather than a row being dropped from both.
        def pcf_mention_principals(ids)
          return [] if ids.empty?

          @pcf_mention_principals ||= {}
          @pcf_mention_principals[ids] ||= User.where(:id => ids).pluck(:id, :login)
        end

        def pcf_mention_logins(ids)
          pcf_mention_principals(ids).map(&:last).reject { |login| login.to_s.empty? }.uniq.sort
        end

        def pcf_mention_user_ids(ids)
          pcf_mention_principals(ids).map(&:first).uniq.sort
        end

        # nil when nothing can match, so callers can fall back to 1=0 / 1=1.
        def pcf_mention_condition(ids)
          logins = pcf_mention_logins(ids)
          user_ids = pcf_mention_user_ids(ids)
          return if logins.empty? && user_ids.empty?

          description = pcf_mention_match(logins, user_ids, "#{Issue.table_name}.description")

          # Skipping journals without notes matters: most rows in the table are
          # attribute changes, and they can never hold a mention.
          notes =
            "EXISTS (SELECT 1 FROM #{Journal.table_name}" \
            " WHERE #{Journal.table_name}.journalized_type = 'Issue'" \
            " AND #{Journal.table_name}.journalized_id = #{Issue.table_name}.id" \
            " AND #{Journal.table_name}.notes IS NOT NULL AND #{Journal.table_name}.notes <> ''" \
            " AND #{pcf_mention_match(logins, user_ids, "#{Journal.table_name}.notes")}" \
            " AND (#{Journal.visible_notes_condition(User.current, :skip_pre_condition => true)}))"

          "(#{description}) OR #{notes}"
        end

        # The column is nullable, and NULL LIKE '...' is UNKNOWN rather than
        # false, which would swallow rows under a NOT.
        #
        # Where a regular expression is available the prefilter is a single
        # "contains an @" and the expression carries every login, so the cost of
        # the filter does not grow with the number of principals selected. On
        # 20 000 issues and 200 000 journals, PostgreSQL takes the same 244 ms
        # for one principal as for twenty one, where one LIKE per login took
        # 304 ms and 1038 ms.
        def pcf_mention_match(logins, user_ids, column)
          conditions = ["#{column} IS NOT NULL"]
          regexp = pcf_mention_regexp(column, logins, user_ids)

          if regexp
            conditions << pcf_like_any_mention(column, user_ids) << regexp
          else
            # No regular expression, so the LIKE has to carry the names itself.
            likes = logins.map { |login| pcf_like_login(column, login) }
            likes += user_ids.map { |id| pcf_like_user_link(column, id) }
            conditions << "(#{likes.join(' OR ')})"
          end

          "(#{conditions.join(' AND ')})"
        end

        # The prefilter, one per form. It stays a prefilter: a text the expression
        # accepts always contains an "@" or a "user#", so the two together select
        # exactly what the expression alone would.
        #
        # "user#" and not "user" on purpose. Both link forms Redmine understands start
        # with "user", so one LIKE '%user%' would cover user:<login> as well — and
        # measured on 20 000 issues that took PostgreSQL from 241 ms to 506 ms, against
        # 332 ms for this. user:<login> is not matched, and that is why.
        def pcf_like_any_mention(column, user_ids)
          patterns = ['%@%']
          patterns << '%user#%' if user_ids.any?

          conditions = patterns.map do |pattern|
            Issue.sanitize_sql([Redmine::Database.like(column, '?'), pattern])
          end
          "(#{conditions.join(' OR ')})"
        end

        def pcf_like_user_link(column, id)
          Issue.sanitize_sql([Redmine::Database.like(column, '?'), "%user##{id}%"])
        end

        # Only the login is escaped: the surrounding % are the wildcards.
        def pcf_like_login(column, login)
          Issue.sanitize_sql(
            [Redmine::Database.like(column, '?'), "%@#{Issue.sanitize_sql_like(login)}%"]
          )
        end

        # PostgreSQL and MySQL agree on the pattern but not on the operator.
        # SQLite has no REGEXP without a user defined function, so it keeps the
        # LIKE alone and accepts the false positives.
        #
        # Logins are compared without regard to case, because that is what
        # Redmine does: its own MENTION_PATTERN carries the /i flag, and logins
        # are unique case insensitively. PostgreSQL's ~* says so in the operator.
        # MySQL's REGEXP instead follows the column's collation, so on a column
        # declared utf8mb4_bin the very same pattern stops matching @JSmith for
        # the login jsmith — a filter that silently disagrees with the
        # notification that prompted it. The inline (?i) states the intent in the
        # pattern, where no collation can override it; both MySQL's ICU engine
        # and MariaDB's PCRE engine honour it.
        def pcf_mention_regexp(column, logins, user_ids)
          branches = []

          if logins.any?
            alternatives = logins.map { |login| pcf_escape_regexp(login) }.join('|')
            branches <<
              "(^|#{MENTION_LEAD})@(#{alternatives})#{MENTION_TRAILING_PUNCT}(#{MENTION_BOUNDARY}|$)"
          end

          # "user##176" as well as "user#176": LINKS_RE's separator is \#\#? and both
          # render as a link to the same person. The ids need no escaping, being
          # integers parsed as whole positive numbers before they reach here.
          branches << "(^|#{LINK_LEAD})user##?(#{user_ids.join('|')})(#{LINK_BOUNDARY}|$)" if
            user_ids.any?

          return if branches.empty?

          # Each branch is wrapped before they are joined, or the alternation inside a
          # branch would bind looser than the join and the pattern would mean something
          # else entirely.
          pattern = branches.map { |branch| "(#{branch})" }.join('|')

          if Redmine::Database.postgresql?
            "#{column} ~* #{Issue.connection.quote(pattern)}"
          elsif Redmine::Database.mysql?
            "#{column} REGEXP #{Issue.connection.quote("(?i)#{pattern}")}"
          end
        end

        # Redmine restricts logins to letters, digits and _ - @ . but an account
        # created before that rule, or through LDAP, may hold anything, so every
        # non alphanumeric character is escaped rather than an expected few.
        def pcf_escape_regexp(login)
          login.gsub(/[^A-Za-z0-9]/) { |char| "\\#{char}" }
        end
      end
    end
  end
end

IssueQuery.prepend(RedmineParentChildFilters::Patches::MentionFilterPatch::InstanceMethods)
