# CHANGELOG
### 0.0.3
* filter on root_issue
* Resolved issue: `SystemStackError (stack level too deep)`  
  Converted `initialize_available_filters` to use `alias_method` 

### 0.0.2
* child filters, when combined, are now considering the same child

### 0.0.1
* initial commit
* filter on parent_tracker
* filter on parent_status
* filter on child_tracker
* filter on child_status
