# frozen_string_literal: true

module RedmineParentChildFilters
  module Patches
    # The one way this plugin registers a filter, shared by the hierarchy filters
    # and the people filters so that all of them obey the same two rules:
    #
    #   * an administrator can switch any of them off, under enable_<name>_filter;
    #   * none of them ever replaces a filter that already exists.
    #
    # The label follows from the name as well (label_filter_<name>), so adding a
    # filter means naming it once rather than three times.
    module FilterRegistration
      def pcf_register_filter(name, options)
        return unless RedmineParentChildFilters.filter_enabled?("enable_#{name}_filter")
        return if pcf_name_taken?(name)

        add_available_filter(name, options.merge(:label => :"label_filter_#{name}"))
      end

      private

      # initialize_available_filters calls super before registering anything, so
      # @available_filters already holds what core and any earlier patch put
      # there. add_available_filter would overwrite it without a word, and a core
      # filter quietly changing meaning is worse than this plugin missing one.
      #
      # The ivar is read directly because available_filters would call
      # initialize_available_filters again.
      def pcf_name_taken?(name)
        return false unless @available_filters&.key?(name)

        RedmineParentChildFilters.warn_once(
          "collision:#{name}",
          "not registering the #{name} filter: #{self.class} already has one under that name"
        )
        true
      end
    end
  end
end
