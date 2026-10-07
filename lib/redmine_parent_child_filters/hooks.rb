# frozen_string_literal: true

module RedmineParentChildFilters
  # Loads the script that renders the "status, with none" filter type in the
  # filter form. In the layout head, after Redmine's own scripts, because it
  # wraps buildFilterRow from application-legacy.js; it does nothing on a page
  # without a filter form.
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(_context = {})
      javascript_include_tag('pcf_filters', :plugin => 'redmine_parent_child_filters')
    end
  end
end
