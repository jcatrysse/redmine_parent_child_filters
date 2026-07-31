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

        # Mentions are written as @login, so the selected principals are resolved
        # to logins. Groups have none and simply drop out. Memoised: Redmine
        # builds the statement several times per request, for the count, the page
        # and any total.
        def pcf_mention_logins(ids)
          return [] if ids.empty?

          @pcf_mention_logins ||= {}
          @pcf_mention_logins[ids] ||=
            User.where(:id => ids).where.not(:login => [nil, '']).pluck(:login).uniq.sort
        end

        # nil when nothing can match, so callers can fall back to 1=0 / 1=1.
        def pcf_mention_condition(ids)
          logins = pcf_mention_logins(ids)
          return if logins.empty?

          description = pcf_mention_match(logins, "#{Issue.table_name}.description")

          # Skipping journals without notes matters: most rows in the table are
          # attribute changes, and they can never hold a mention.
          notes =
            "EXISTS (SELECT 1 FROM #{Journal.table_name}" \
            " WHERE #{Journal.table_name}.journalized_type = 'Issue'" \
            " AND #{Journal.table_name}.journalized_id = #{Issue.table_name}.id" \
            " AND #{Journal.table_name}.notes IS NOT NULL AND #{Journal.table_name}.notes <> ''" \
            " AND #{pcf_mention_match(logins, "#{Journal.table_name}.notes")}" \
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
        def pcf_mention_match(logins, column)
          conditions = ["#{column} IS NOT NULL"]
          regexp = pcf_mention_regexp(column, logins)

          if regexp
            conditions << pcf_like_any_mention(column) << regexp
          else
            # No regular expression, so the LIKE has to carry the logins itself.
            conditions << "(#{logins.map { |login| pcf_like_login(column, login) }.join(' OR ')})"
          end

          "(#{conditions.join(' AND ')})"
        end

        def pcf_like_any_mention(column)
          Issue.sanitize_sql([Redmine::Database.like(column, '?'), '%@%'])
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
        def pcf_mention_regexp(column, logins)
          alternatives = logins.map { |login| pcf_escape_regexp(login) }.join('|')
          pattern =
            "(^|#{MENTION_LEAD})@(#{alternatives})#{MENTION_TRAILING_PUNCT}(#{MENTION_BOUNDARY}|$)"

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
