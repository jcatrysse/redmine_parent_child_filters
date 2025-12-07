# Redmine Parent Child Filters Plugin

**Version: 0.2.0 is in the alpha stage: do not use it in production yet!**

This plugin provides advanced filtering capabilities for issues in Redmine based on their hierarchical relationships, allowing you to filter based on the `trackers` and `status` of parent and child issues.

Link to Redmine plugin page: [Redmine Parent Child Filters Plugin](https://www.redmine.org/plugins/redmine_parent_child_filters)

## Compatibility
* Redmine 4.x and Redmine 5.x.

## Features
* **Root Level Filtering**: Enables you to filter issues based on the root-level attributes.
    * `root`
    * `root_tracker`
    * `root_status`

* **Immediate Parent Filtering**: Target issues based on their immediate parent attributes.
    * `parent_tracker`
    * `parent_status`

* **Any Parent Filtering**: Extend your filtering criteria to any level of the issue's ancestry.
    * `parent_tracker` (any parent)
    * `parent_status` (any parent)

* **Depth-Based Parent Filtering**: A powerful feature allowing filtering based on the depth of the issue's ancestry. If multiple depths are selected, the filter considers only the smallest depth.
    * `parent_tracker` (with depth selection)
    * `parent_status` (with depth selection)

* **Child Level Filtering**: Directly target child issues with the following attributes.
    * `child_tracker`
    * `child_status`

* **Tree Filters**: Surface the entire hierarchy when a parent/child match is found, and also show standalone issues (no parents or children) that match the same tracker or status criteria without changing the behavior of the existing filters.
    * `tree_has_parent_or_child` (can be used to filter standalone issues or issues with parents or children)
    * `tree_tracker` (tree-wide tracker match)
    * `tree_status` (tree-wide status match)
    * `tree_parent_tracker`
    * `tree_parent_status`
    * `tree_child_tracker`
    * `tree_child_status`

* **Additional Operators**: Enhance your filtering capabilities with additional operators.
    * Operator `not equal to` on `start_date` and `end_date`

* **Settings**: The plugin provides a dedicated Settings menu where 
    * Each filter can be enabled or disabled as per your requirements. 
    * Additionally, you can configure the depth settings for depth-based filters.

## Install
Follow the commands below for a smooth installation:
* Navigate to your plugins directory:
    * `$ cd $RAILS_ROOT/plugins`
* Clone the repository:
    * `$ git clone https://github.com/jcatrysse/redmine_parent_child_filters.git`
* Migrate the plugin:
    * `$ bundle exec rake redmine:plugins:migrate NAME=redmine_parent_child_filters RAILS_ENV=production`

Don't forget to restart your Redmine afterward!

## Uninstall
* Simply remove the plugin folder.
* Restart Redmine for the changes to take effect.

## Development

Tests can be run using:
```bash
RAILS_ENV=test bundle exec rspec plugins/redmine_parent_child_filters/spec
```

## License
Distributed under the MIT License. Enjoy the flexibility and freedom it brings!
