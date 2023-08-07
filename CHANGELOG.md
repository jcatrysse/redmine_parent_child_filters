# CHANGELOG
### 0.0.3
* Filter on `root`
* Filter on `root_tracker`
* Filter on `root_status`
* Operator `not equal to` on `start_date` and `end_date`
* Resolved issue: `SystemStackError (stack level too deep)`  
  Converted `initialize_available_filters` to use `alias_method` 

### 0.0.2
* Filters `child_tracker` and `child_status`, when combined, are now considering the same child

### 0.0.1
* Initial commit
* Filter on `parent_tracker`
* Filter on `parent_status`
* Filter on `child_tracker`
* Filter on `child_status`
