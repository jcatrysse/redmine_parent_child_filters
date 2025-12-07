# CHANGELOG

## 0.2.0 (ALPHA version: do not use in production)
* Add tree-wide filters to surface complete hierarchies alongside existing parent/child filters.
* Document and translate the new tree filter options and settings toggles.
* Introduce RSpec test coverage for the full filter suite.
* Introduce GitHub actions.

## 0.1.0
* Optimize UX for `specific depth` filters.

## 0.0.5
* Filter on `parent_tracker` (specific depth)
* Filter on `parent_status` (specific depth)
* Prefix plugin name with `Redmine`

## 0.0.4
* Filter on `parent_tracker` (any depth)
* Filter on `parent_status` (any depth)
* Add plugin settings to enable filters

## 0.0.3
* Filter on `root`
* Filter on `root_tracker`
* Filter on `root_status`
* Operator `not equal to` on `start_date` and `end_date`
* Resolved issue: `SystemStackError (stack level too deep)`  
  Converted `initialize_available_filters` to use `alias_method` 

## 0.0.2
* Filters `child_tracker` and `child_status`, when combined, are now considering the same child

## 0.0.1
* Initial commit
* Filter on `parent_tracker`
* Filter on `parent_status`
* Filter on `child_tracker`
* Filter on `child_status`
