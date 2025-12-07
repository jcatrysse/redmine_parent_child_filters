require 'rspec'
require 'ostruct'

# Stub Rails' require_dependency to avoid missing framework behavior
unless defined?(require_dependency)
  def require_dependency(*)
  end
end

def l(key)
  key
end

module Setting
  def self.plugin_redmine_parent_child_filters
    {
      'enable_root_id_filter' => false,
      'enable_root_tracker_id_filter' => false,
      'enable_root_status_id_filter' => false,
      'enable_parent_tracker_id_filter' => false,
      'enable_parent_status_id_filter' => false,
      'enable_a_parent_tracker_id_filter' => false,
      'enable_a_parent_status_id_filter' => false,
      'enable_a_specific_parent_tracker_id_filter' => false,
      'enable_a_specific_parent_status_id_filter' => false,
      'enable_child_tracker_id_filter' => false,
      'enable_child_status_id_filter' => false,
      'enable_tree_has_parent_or_child_filter' => true,
      'enable_tree_tracker_id_filter' => true,
      'enable_tree_status_id_filter' => true,
      'enable_tree_parent_tracker_id_filter' => true,
      'enable_tree_parent_status_id_filter' => true,
      'enable_tree_child_tracker_id_filter' => true,
      'enable_tree_child_status_id_filter' => true,
      'min_depth' => '1',
      'max_depth' => '5'
    }
  end
end

class Issue
  def self.table_name
    'issues'
  end
end

class IssueStatus
  def self.table_name
    'issue_statuses'
  end
end

module ActiveRecord
  class Base
    def self.connection
      @connection ||= OpenStruct.new(quoted_false: 'FALSE', quoted_true: 'TRUE')
    end
  end
end

class IssueQuery
  def self.connection
    ActiveRecord::Base.connection
  end

  def initialize_available_filters
  end

  def available_filters
    @available_filters ||= {}
  end

  def add_available_filter(field, options)
    available_filters[field] = options
  end

  def trackers
    []
  end

  def issue_statuses_values
    []
  end

  def filters
    @filters ||= {}
  end
end
