# frozen_string_literal: true

module RedmineParentChildFilters
  # The hard ceiling on how deep the "parent by level" filters may look. Each
  # level costs one self join, so this is what stops a filter value from turning
  # into an unbounded query. The settings form offers 1..MAX_DEPTH and the query
  # refuses anything above it, both from this one constant.
  #
  # Ten is already more than any real issue hierarchy needs; raising it means
  # accepting that a single filter can join the issues table that many times.
  MAX_DEPTH = 10

  # Single definition of what an "enabled" plugin setting means, shared by the
  # query patch and the settings form.
  #
  # Checkboxes post "1" when ticked and nothing at all when unticked, so the
  # stored value is either "1" or absent. A value of "0" or "false" can only come
  # from the console or the REST API, and used to read as enabled.
  def self.enabled?(value)
    value.present? && !%w[0 false].include?(value.to_s)
  end

  def self.filter_enabled?(key)
    enabled?(Setting.plugin_redmine_parent_child_filters[key])
  end

  # Logs a message the first time it is asked, and never again for the same key.
  #
  # Filter registration runs once per query object, so a condition that holds at
  # all holds thousands of times a day. Concurrent::Map comes with Rails and its
  # put_if_absent is atomic, which a plain Hash under Puma is not.
  WARNED = Concurrent::Map.new
  private_constant :WARNED

  def self.warn_once(key, message)
    return unless WARNED.put_if_absent(key, true).nil?

    Rails.logger&.warn("[redmine_parent_child_filters] #{message}")
  end

  # The levels the depth filters may use, as an ascending range inside
  # 1..MAX_DEPTH.
  #
  # Settings are strings that reach the database through a form, the console or
  # the REST API, so every one of them may be missing, empty, negative, reversed
  # or absurd. Rather than trust the form to have prevented that, the values are
  # normalised here, in the one place both the form and the query read.
  def self.depth_range
    settings = Setting.plugin_redmine_parent_child_filters
    min = clamp_depth(settings['min_depth'])
    max = clamp_depth(settings['max_depth'])

    # A reversed pair is a mistake, not a request for an empty range: honour the
    # minimum the administrator picked and widen the maximum to match.
    max = min if max < min

    min..max
  end

  # to_i on a non numeric string is 0, which is below the floor, so unusable
  # settings all collapse onto 1 rather than needing a separate check.
  def self.clamp_depth(value)
    value.to_i.clamp(1, MAX_DEPTH)
  end
  private_class_method :clamp_depth
end
