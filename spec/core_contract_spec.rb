# frozen_string_literal: true

require_relative 'spec_helper'

# One example per assumption the plugin makes about Redmine, so that an upgrade
# which moves any of them fails here, by name, instead of producing wrong SQL or
# a 500 somewhere else. COMPATIBILITY.md is the prose version of this file; the
# two are meant to be read together.
RSpec.describe 'what the plugin assumes about Redmine' do
  let(:query) { IssueQuery.new(:name => '_') }

  describe 'Query, the filter API' do
    it 'registers a filter through add_available_filter and reads it back' do
      query.add_available_filter('pcf_contract', :type => :list, :values => [%w[a a]])

      expect(query.available_filters['pcf_contract'][:type]).to eq(:list)
    end

    it 'keeps available_filters in insertion order' do
      keys = query.available_filters.keys
      # The plugin's group is appended to the dropdown in this order, so a change
      # here scrambles it.
      expect(keys.index('child_tracker_id')).to be < keys.index('child_status_id')
      expect(keys.index('root_id')).to be < keys.index('child_tracker_id')
    end

    it 'resolves a lambda passed as :values only when asked' do
      called = false
      query.add_available_filter('pcf_lazy', :type => :list,
                                             :values => lambda {
                                               called = true
                                               [%w[a a]]
                                             })

      expect(called).to be false
      expect(query.available_filters['pcf_lazy'][:values]).to eq([%w[a a]])
      expect(called).to be true
    end

    it 'translates :label into :name' do
      query.add_available_filter('pcf_named', :type => :list, :values => [],
                                              :label => :label_filter_child_status_id)

      expect(query.available_filters['pcf_named'][:name])
        .to eq(I18n.t(:label_filter_child_status_id))
    end

    # The people filters use the assignee and the description only while the
    # query offers Redmine's own filter on them (a plugin hiding the field removes
    # it). A Redmine that stopped offering them would silently narrow both.
    it 'offers the assignee and the description filters on an issue query' do
      expect(query.available_filters.keys).to include('assigned_to_id', 'description')
    end

    # The plugin validates the values of its date "is not" operator by extending
    # Redmine's own validation and reporting through Redmine's own message.
    it 'validates filters in validate_query_filters and reports through add_filter_error' do
      expect(Query.private_method_defined?(:validate_query_filters) || Query.method_defined?(:validate_query_filters)).to be true
      expect(Query.private_method_defined?(:add_filter_error) || Query.method_defined?(:add_filter_error)).to be true
      expect(Query._validate_callbacks.map(&:filter)).to include(:validate_query_filters)
    end

    it 'exposes delete_available_filter' do
      expect(query).to respond_to(:delete_available_filter)
    end

    it 'exposes the current filters and their operators' do
      query.filters = {}
      query.add_filter('child_tracker_id', '=', [Tracker.first.id.to_s])

      expect(query.operator_for('child_tracker_id')).to eq('=')
      expect(query.filters['child_tracker_id'][:values]).to eq([Tracker.first.id.to_s])
    end

    it 'keeps operators_by_filter_type a class attribute of type to operator list' do
      expect(Query).to respond_to(:operators_by_filter_type)
      expect(Query.operators_by_filter_type).to be_a(Hash)
      expect(Query.operators_by_filter_type[:list]).to include('=', '!')
    end

    # The plugin reuses this for the status history operators against an alias, so
    # it needs the five argument form. It feature-detects the *operators* already;
    # the signature is what this pins.
    it 'accepts five positional arguments on sql_for_field' do
      expect(query.method(:sql_for_field).arity.abs).to be >= 5

      sql = query.send(:sql_for_field, 'status_id', '=', [IssueStatus.first.id.to_s],
                       'some_alias', 'status_id')
      expect(sql).to include('some_alias')
    end
  end

  describe 'the visibility condition' do
    # The plugin aliases this condition by rewriting two table names. That is only
    # sound while those are the only tables it names outside a subquery of its own.
    it 'mentions no table the plugin cannot alias' do
      %w[admin non_member].each do |kind|
        user = kind == 'admin' ? User.find(1) : User.new
        condition = Issue.visible_condition(user)

        # Every <table>. reference in the condition.
        tables = condition.scan(/\b([a-z_]+)\./).flatten.uniq
        # issues and projects are rewritten; em is the alias core gives
        # enabled_modules inside its own correlated subquery, so it is self
        # contained and needs no rewriting.
        expect(tables - %w[issues projects em]).to eq([]),
                                                   "#{kind}: unexpected table(s) in visible_condition: #{tables.inspect}"
      end
    end

    it 'carries no string a user could influence' do
      condition = Issue.visible_condition(User.find(2))
      quoted = condition.scan(/'([^']*)'/).flatten

      # Only the project module name, which comes from Redmine's own code.
      expect(quoted - ['issue_tracking']).to eq([])
    end

    it 'leaves no unaliased reference behind after the rewrite' do
      query.filters = {}
      query.add_filter('child_tracker_id', '=', [Tracker.first.id.to_s])
      subquery = query.statement[/EXISTS \(SELECT 1 FROM #{Issue.table_name} child.*?\)\)/m]

      expect(subquery).not_to be_nil
      expect(subquery).to include('child_projects')
      # Inside the child subquery, the only issues. references are the outer
      # correlation on issues.id; nothing else may still say issues. or projects.
      expect(subquery.scan(/\bprojects\./)).to eq([])
    end
  end

  describe 'Journal, for private notes' do
    it 'exposes visible_notes_condition with skip_pre_condition' do
      condition = Journal.visible_notes_condition(User.find(2), :skip_pre_condition => true)

      expect(condition).to be_a(String)
      expect(condition).to include(Journal.table_name)
    end

    # The first project filter rewrites journals to an alias and leaves projects
    # pointing at the outer issue's project, as core's history operators do.
    it 'mentions no table but journals and projects' do
      [User.find(1), User.find(2), User.anonymous].each do |user|
        condition = Journal.visible_notes_condition(user, :skip_pre_condition => true)
        tables = condition.scan(/\b([a-z_]+)\./).flatten.uniq

        expect(tables - [Journal.table_name, Project.table_name, 'em']).to eq([]), "#{user.login}: #{tables.inspect}"
      end
    end
  end

  describe 'the project history' do
    # Both project filters read moves from the journal; an issue that is moved
    # without one would read as never having moved.
    it 'journals project_id' do
      expect(Issue.new.journalized_attribute_names).to include('project_id')
    end

    # Redmine moves subtasks along with their parent in after_project_change,
    # through child.send(:project=, project, true) and child.save, without a
    # journal. The plugin hooks exactly that project= call to give the subtask
    # one. Asserted with the plugin's journaling switched off: if a Redmine starts
    # journaling these moves itself, this fails, and the patch (which then does
    # nothing, since the subtask already carries a journal) can be retired.
    it 'moves subtasks along with their parent without a journal of its own' do
      previous = Setting.plugin_redmine_parent_child_filters
      Setting.plugin_redmine_parent_child_filters = previous.merge('journal_subtask_moves' => '0')
      from, to = %w[pcf-contract-from pcf-contract-to].map do |identifier|
        project = Project.create!(:name => identifier, :identifier => identifier, :is_public => true)
        project.trackers = Tracker.all
        project.enabled_module_names = ['issue_tracking']
        project
      end
      parent = create_issue(project: from)
      child = create_issue(project: from, parent: parent)

      parent = Issue.find(parent.id)
      parent.init_journal(User.find(1))
      parent.project = to
      parent.save!

      expect(child.reload.project_id).to eq(to.id)
      expect(JournalDetail.joins(:journal)
                          .where(:journals => {:journalized_type => 'Issue', :journalized_id => child.id},
                                 :property => 'attr', :prop_key => 'project_id')).to be_empty
    ensure
      Setting.plugin_redmine_parent_child_filters = previous
    end

    it 'keeps after_project_change private, and project= taking keep_tracker' do
      expect(Issue.private_method_defined?(:after_project_change)).to be(true)
      expect(Issue.instance_method(:project=).super_method.arity).to eq(-2)
    end

    # If core starts offering history on its own project filter, the plugin's
    # project_history_id becomes a duplicate and should be retired.
    it 'still offers only is and is not on the core project filter' do
      expect(IssueQuery.new.available_filters['project_id'][:type]).to eq(:list)
    end
  end

  describe 'Active Record sanitisation' do
    # What the plugin needs is that the placeholder is substituted and the value
    # is quoted for this adapter. How an Integer comes out differs — PostgreSQL
    # renders 1, MySQL renders '1' — so pinning the exact string would only assert
    # which database the suite happened to run against.
    it 'exposes sanitize_sql publicly, and it binds the placeholder' do
      expect(Issue.respond_to?(:sanitize_sql)).to be true

      expect(Issue.sanitize_sql(['a = ?', 1])).to match(/\Aa = '?1'?\z/)
      expect(Issue.sanitize_sql(["a = ?", "it's"])).not_to include("= it's")
    end

    it 'escapes LIKE wildcards' do
      expect(Issue.sanitize_sql_like('a_b%c')).to eq('a\\_b\\%c')
    end
  end

  describe 'Redmine::Database' do
    it 'answers which engine is in use, and exactly one of them' do
      engines = [Redmine::Database.postgresql?, Redmine::Database.mysql?,
                 Redmine::Database.sqlite?]

      expect(engines.count(true)).to eq(1)
    end

    it 'builds a case insensitive LIKE with a placeholder' do
      expect(Redmine::Database.like('a.b', '?')).to include('?')
    end
  end

  describe 'the available_filters ivar the dropdown patch swaps' do
    it 'is what available_filters reads' do
      query.available_filters # force initialisation

      query.instance_variable_set(:@available_filters, {'only_this' => nil})
      expect(query.available_filters.keys).to eq(['only_this'])
    end

    it 'is restored even when core raises' do
      view = ActionView::Base.empty
      view.extend(ApplicationHelper)
      view.extend(QueriesHelper)
      view.extend(Redmine::I18n)

      before = query.available_filters
      allow(view).to receive(:grouped_options_for_select).and_raise(RuntimeError, 'boom')

      expect { view.filters_options_for_select(query) }.to raise_error('boom')
      expect(query.available_filters).to be(before)
    end
  end

  describe 'the mention pattern the filter is measured against' do
    it 'still exists where the plugin looks for it' do
      expect(Redmine::Acts::Mentionable::InstanceMethods::MENTION_PATTERN).to be_a(Regexp)
    end

    it 'is still case insensitive, which is why the filter is too' do
      expect(Redmine::Acts::Mentionable::InstanceMethods::MENTION_PATTERN.options &
             Regexp::IGNORECASE).to eq(Regexp::IGNORECASE)
    end

    # Mentions are still not stored anywhere, which is the whole reason the filter
    # reads the text. If a future Redmine adds a table, the filter should use it.
    it 'has no table behind it' do
      expect(ActiveRecord::Base.connection.tables.grep(/mention/)).to eq([])
    end
  end
end
