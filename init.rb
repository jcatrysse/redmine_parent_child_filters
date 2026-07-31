# frozen_string_literal: true

Redmine::Plugin.register :redmine_parent_child_filters do
  name 'Redmine Parent Child Filters Plugin'
  author 'Jan Catrysse'
  description 'Filter issues by their parent, child and tree relationships, and by who is involved in or mentioned on them'
  version '1.0.0'
  url 'https://github.com/jcatrysse/redmine_parent_child_filters'
  author_url 'https://github.com/jcatrysse'

  requires_redmine version_or_higher: '5.0'

  settings default: {
    'enable_root_id_filter' => true,
    'enable_root_tracker_id_filter' => true,
    'enable_root_status_id_filter' => true,
    'enable_parent_tracker_id_filter' => true,
    'enable_parent_status_id_filter' => true,
    'enable_a_parent_tracker_id_filter' => true,
    'enable_a_parent_status_id_filter' => true,
    'enable_a_specific_parent_tracker_id_filter' => true,
    'enable_a_specific_parent_status_id_filter' => true,
    'enable_child_tracker_id_filter' => true,
    'enable_child_status_id_filter' => true,
    'enable_a_child_tracker_id_filter' => true,
    'enable_a_child_status_id_filter' => true,
    'enable_tree_has_parent_or_child_filter' => true,
    'enable_tree_tracker_id_filter' => true,
    'enable_tree_status_id_filter' => true,
    'enable_tree_parent_tracker_id_filter' => true,
    'enable_tree_parent_status_id_filter' => true,
    'enable_tree_child_tracker_id_filter' => true,
    'enable_tree_child_status_id_filter' => true,
    'enable_involved_id_filter' => true,
    'enable_mentioned_id_filter' => true,
    'enable_involved_or_mentioned_id_filter' => true,
    'min_depth' => '1',
    'max_depth' => '5'
  }, partial: 'settings/parent_child_filters_settings'
end

require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/issue_query_patch'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/principal_filter_support'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/involvement_filter_patch'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/mention_filter_patch'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/queries_helper_patch'
require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/query_include'
