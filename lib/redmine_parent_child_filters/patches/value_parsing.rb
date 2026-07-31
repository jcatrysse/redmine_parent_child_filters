# frozen_string_literal: true

module RedmineParentChildFilters
  module Patches
    # Turning what arrived in the request into something that may be put in SQL.
    #
    # Kept apart from the SQL builders because it is the one part with no query
    # state at all: same input, same answer, always. That is also why it carries
    # the largest share of the specs (spec/value_parsing_spec.rb).
    module ValueParsing
      # Turns filter values into a comma separated id list, or nil when none of
      # them is one.
      #
      # Redmine core scans for digit runs here (value.to_s.scan(/\d+/)), which
      # reads "1 OR 2" as 1,2 and "user-123" as 123. Only digits survive either
      # way, so neither can inject SQL, but core's reading answers a question
      # nobody asked: a corrupted saved query or a mistyped url quietly returns
      # real rows. A value is a whole positive id, or a comma separated list of
      # them, or it is not a value.
      #
      # An unusable value is dropped rather than raising, and a filter left with
      # nothing usable matches nothing — see pcf_no_value_condition. Dropping
      # one of several selected values is how the depth filters already behave.
      def pcf_id_list(values)
        ids = Array(values).flat_map { |value| pcf_parse_ids(value) }.uniq
        ids.empty? ? nil : ids.join(',')
      end

      # "12" and "3, 5,8" are id lists. "", "0", "-1", "1 OR 2", "user-123" and
      # a full width "１２" are not: \d is ASCII only in Ruby, so digits from
      # another script never pass. One bad element rejects the whole value,
      # because "3,x,8" is not a list of ids.
      def pcf_parse_ids(value)
        parts = value.to_s.split(',', -1)
        return [] if parts.empty?

        parts.map do |part|
          part = part.strip
          return [] unless /\A\d+\z/.match?(part)

          id = part.to_i
          return [] if id.zero?

          id
        end
      end

      # Condition to fall back on when a filter holds no usable value:
      # matches nothing when asking for a match, everything when asking for
      # the absence of one.
      def pcf_no_value_condition(operator)
        pcf_negated?(operator) ? '1=1' : '1=0'
      end

      # Reads the one filter whose value is a yes/no rather than an id. The select
      # offers exactly "1" and "0", so anything else is a corrupted saved query or a
      # hand written url, and nil says so.
      #
      # This used to read `value.include?('yes') || value.include?('1')`, which is
      # array membership rather than a substring test, so it never matched free text
      # — but it did read every unrecognised value as "no", quietly answering the
      # opposite question instead of failing closed like every other filter here.
      def pcf_parse_flag(values)
        flags = Array(values).map(&:to_s).reject(&:empty?).uniq
        return nil unless flags.size == 1

        case flags.first
        when '1' then true
        when '0' then false
        end
      end

      # Parses "<id>:<depth>" filter values into {depth => [ids]}. Depth is
      # bounded by the configured maximum so that a crafted value cannot
      # generate an unbounded number of joins, and malformed values are
      # dropped rather than raising.
      def pcf_parse_depth_values(values)
        max_depth = pcf_max_depth

        Array(values).each_with_object({}) do |value, by_depth|
          id, depth = value.to_s.split(':', 2)
          ids = pcf_parse_ids(id)
          next unless ids.size == 1 && /\A\d+\z/.match?(depth.to_s)

          depth = depth.to_i
          # Out of range is dropped rather than clamped: clamping would answer
          # about a level the user did not ask about.
          next unless depth.between?(1, max_depth)

          (by_depth[depth] ||= []) << ids.first
          by_depth[depth] = by_depth[depth].uniq
        end.sort.to_h
      end
    end
  end
end
