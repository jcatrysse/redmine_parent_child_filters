Redmine::Plugin.register :redmine_parent_child_filters do
  name 'Parent Child Filters Plugin'
  author 'Jan Catrysse'
  description 'Search issues by parent and child tracker and status'
  version '0.0.1'
  url 'https://github.com/jcatrysse/redmine_parent_child_filters'
  author_url 'https://github.com/jcatrysse'

  requires_redmine version_or_higher: '4.0'

  require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/issue_query_patch'
  require File.dirname(__FILE__) + '/lib/redmine_parent_child_filters/patches/queries_helper_patch'
end
