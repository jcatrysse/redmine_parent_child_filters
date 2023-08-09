module RedmineParentChildFilters
  module Hooks
    class ViewLayoutsBaseHtmlHeadHook < Redmine::Hook::ViewListener
      render_on :view_layouts_base_html_head, :partial => 'redmine_parent_child_filters/add_custom_filters_js'
    end
  end
end
