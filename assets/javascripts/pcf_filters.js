// Renders the filter type :pcf_list_status in Redmine's filter form: Redmine's
// status type plus "none", for the status filters of redmine_parent_child_filters
// whose relative may be missing (see lib/.../patches/query_include.rb).
//
// buildFilterRow takes the operators from operatorByType[type] and draws the
// value list for the types it knows, so a type of its own would get operators
// but no values. For the duration of one call the filter is presented as
// "list_status" with the longer operator list, then both are put back: the same
// swap and restore the plugin does on the server for the dropdown grouping.
(function() {
  var TYPE = 'pcf_list_status';
  var original = window.buildFilterRow;
  if (typeof original !== 'function') return;

  window.buildFilterRow = function(field, operator, values) {
    var options = (typeof availableFilters !== 'undefined') ? availableFilters[field] : null;
    if (!options || options['type'] !== TYPE || !operatorByType[TYPE]) {
      return original.apply(this, arguments);
    }
    var statusOperators = operatorByType['list_status'];
    options['type'] = 'list_status';
    operatorByType['list_status'] = operatorByType[TYPE];
    try {
      return original.apply(this, arguments);
    } finally {
      operatorByType['list_status'] = statusOperators;
      options['type'] = TYPE;
    }
  };
})();
