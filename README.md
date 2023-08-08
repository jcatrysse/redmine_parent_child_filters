# Redmine Parent Child Filters Plugin
This plugin allows filtering on the `trackers` and `status` of parent and child issues.

Link to Redmine plugin page: https://www.redmine.org/plugins/redmine_parent_child_filters

## Compatibility
* Version 0.0.1 >= Redmine 4 (including Redmine 5)

## Features
* Filter on `root`
* Filter on `root_tracker`
* Filter on `root_status`
* Filter on `parent_tracker`
* Filter on `parent_status`
* Filter on `parent_tracker` (any parent)
* Filter on `parent_status` (any parent)
* Filter on `child_tracker`
* Filter on `child_status`
* Operator `not equal to` on `start_date` and `end_date`

## Install
Type below commands:
* $ `cd $RAILS_ROOT/plugins`  
* $ `git clone https://github.com/jcatrysse/redmine_parent_child_filters.git`  

Then, restart your Redmine.

## Uninstall
* Remove plugin folder
* Restart Redmine

## License
GPLv2
