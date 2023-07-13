# Redmine Parent Child Filters Plugin

This plugin allows filtering on the `trackers` and `status` of parent and child issues.

Link to Redmine plugin page: https://www.redmine.org/plugins/redmine_parent_child_filters

## Compatibility

* Version 0.0.1 >= Redmine 4 (including Remdine 5)

## Features

* initial commit
* filter in parent_tracker
* filter in parent_status
* filter in child_tracker
* filter in child_status

## Install

* Read the Redmine plugin installation wiki: http://www.redmine.org/wiki/redmine/Plugins
* Restart Redmine

## Uninstall

* Run migration backwards: `bundle exec rake redmine:plugins:migrate NAME=redmine_parent_child_filters VERSION=0 RAILS_ENV=production`
* Remove plugin folder
* Restart Redmine

## License

GPLv2
