Redmine::Plugin.register :redmine_parent_child_filters do
  name 'Parent Child Filters Plugin'
  author 'Jan Catrysse'
  description 'Search issues by parent and child tracker and status'
  version '0.0.4'
  url 'https://github.com/jcatrysse/redmine_parent_child_filters'
  author_url 'https://github.com/jcatrysse'

  requires_redmine version_or_higher: '4.0'

  settings default: {
    'enable_root_id_filter' => true,
    'enable_root_tracker_id_filter' => true,
    'enable_root_status_id_filter' => true,
    'enable_parent_tracker_id_filter' => true,
    'enable_parent_status_id_filter' => true,
    'enable_a_parent_tracker_id_filter' => true,
    'enable_a_parent_status_id_filter' => true,
    'enable_child_tracker_id_filter' => true,
    'enable_child_status_id_filter' => true,
  }, partial: 'settings/parent_child_filters_settings'
end

require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/issue_query_patch'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/queries_helper_patch'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/query_include'
