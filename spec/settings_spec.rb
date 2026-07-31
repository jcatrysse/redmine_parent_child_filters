# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'plugin settings' do
  let(:session) { ActionDispatch::Integration::Session.new(Rails.application) }

  before do
    session.post '/login', :params => {:username => 'admin', :password => 'admin'}
  end

  def settings_page
    session.get '/settings/plugin/redmine_parent_child_filters'
    session.response.body
  end

  it 'renders every checkbox and depth selector' do
    body = settings_page

    expect(session.response.status).to eq(200)
    Setting.plugin_redmine_parent_child_filters.each_key do |key|
      expect(body).to include(%(name="settings[#{key}]")), "missing input for #{key}"
    end
  end

  it 'links each label to the input it toggles' do
    body = settings_page

    expect(body).to include(%(for="settings_enable_root_id_filter"))
    expect(body).to include(%(id="settings_enable_root_id_filter"))
    expect(body).to include(%(for="settings_min_depth"))
  end

  it 'shows a translated label rather than a missing translation' do
    expect(settings_page).not_to include('translation missing')
  end

  # A setting stored as '0' used to read as enabled, both here and in the query.
  it 'renders a setting stored as 0 as unchecked' do
    Setting.plugin_redmine_parent_child_filters =
      Setting.plugin_redmine_parent_child_filters.merge('enable_tree_tracker_id_filter' => '0')

    body = settings_page
    checkbox = body[/<input[^>]*id="settings_enable_tree_tracker_id_filter"[^>]*>/]

    expect(checkbox).not_to be_nil
    expect(checkbox).not_to include('checked')
    expect(IssueQuery.new.available_filters.keys).not_to include('tree_tracker_id')
  end

  it 'does not define a helper method on the view class' do
    settings_page

    expect(ActionView::Base.instance_methods).not_to include(:render_check_box)
  end

  # A browser sends nothing for an unticked box, so without the hidden field "off"
  # would be stored as the absence of a key rather than as a value. Redmine's own
  # setting_check_box does the same.
  it 'posts an explicit 0 for every unticked box, as core does' do
    body = settings_page
    toggles = Setting.plugin_redmine_parent_child_filters.keys.grep(/\Aenable_/)

    missing = toggles.reject do |key|
      body.include?(%(<input type="hidden" name="settings[#{key}]" value="0" autocomplete="off" />))
    end
    expect(missing).to eq([]), "no hidden 0 for #{missing.join(', ')}"
  end

  it 'stores 0 rather than dropping the key when a box is unticked' do
    session.post '/settings/plugin/redmine_parent_child_filters',
                 :params => {:settings => {'enable_root_id_filter' => '0'}}

    expect(Setting.plugin_redmine_parent_child_filters['enable_root_id_filter']).to eq('0')
    expect(IssueQuery.new.available_filters.keys).not_to include('root_id')
  end

  # The page has to be right with scripting off: the plugin ships no JavaScript, so
  # the server is the only thing that can normalise a reversed pair. Asserted on the
  # partial rather than the rendered page, which of course carries Redmine's own
  # scripts.
  it 'contributes no script tag and no inline handler' do
    partial = File.read(
      File.expand_path('../app/views/settings/_parent_child_filters_settings.html.erb', __dir__)
    )

    expect(partial).not_to include('<script')
    expect(partial).not_to match(/\son(?:click|change|load|submit)=/)
    expect(Dir[File.expand_path('../assets/**/*.js', __dir__)]).to eq([])
  end

  it 'states what a level means, in the interface, using core\'s own wording' do
    body = settings_page

    expect(body).to include("1 = #{I18n.t(:field_parent_issue)}")
  end

  it 'shows the range the filters will really use, not just what is stored' do
    Setting.plugin_redmine_parent_child_filters =
      Setting.plugin_redmine_parent_child_filters.merge('min_depth' => '4', 'max_depth' => '2')

    # Reversed on purpose: the selects still show what is stored, the hint shows
    # what the filters do with it.
    expect(settings_page).to include('4–4')
  end

  # The mention filters read issue text, so they cost more than the rest. An
  # administrator ticking the box sees only the settings page, not the readme, so the
  # warning has to be there — translated, in their own language.
  it 'warns about the cost of the mention filters, in the reader\'s language' do
    expect(settings_page).to include(ERB::Util.html_escape(I18n.t(:text_mention_filters_cost)))

    User.find(1).update_columns(:language => 'nl')
    expect(settings_page)
      .to include(ERB::Util.html_escape(I18n.t(:text_mention_filters_cost, :locale => :nl)))
  ensure
    User.find(1).update_columns(:language => 'en')
  end

  # Accessibility properties of the rendered page. Deliberately asserted here rather
  # than through a browser: the plugin ships no JavaScript, so there is no client
  # behaviour left for a Capybara stack to exercise, and these are the properties
  # that actually break — a duplicate id silently detaches a label from its input.
  describe 'accessibility' do
    it 'gives every input exactly one id, and no id twice' do
      ids = settings_page.scan(/<(?:input|select)[^>]*\bid="([^"]+)"/).flatten

      expect(ids.uniq.size).to eq(ids.size), "duplicate ids: #{ids.tally.select { |_, n| n > 1 }.keys}"
    end

    it 'points every label at an input that exists' do
      body = settings_page
      ids = body.scan(/<(?:input|select)[^>]*\bid="([^"]+)"/).flatten
      # Only the labels the plugin's own partial renders.
      targets = body.scan(/<label for="(settings_[^"]+)"/).flatten

      expect(targets).not_to be_empty
      expect(targets - ids).to eq([]), "labels point at nothing: #{(targets - ids).join(', ')}"
    end

    it 'groups the checkboxes with a legend a screen reader can announce' do
      body = settings_page

      expect(body.scan(/<fieldset[^>]*class="box tabular settings"/).size).to eq(4)
      expect(body.scan(%r{<legend>([^<]+)</legend>}).flatten)
        .to include(I18n.t(:label_general_filters_settings), I18n.t(:label_tree_filters_settings))
    end

    # A long translation must not be truncated or lost. German is among the longest
    # of the fifty for these labels. The locale comes from the request, not from
    # I18n.locale in the example, so it is the user's language that has to change.
    it 'renders a long translation intact' do
      User.find(1).update_columns(:language => 'de')
      body = settings_page

      expect(body).to include(ERB::Util.html_escape(I18n.t(:label_filter_child_status_id,
                                                           :locale => :de)))
      expect(body).not_to include('translation missing')
      # 24 characters against 15 in English: proof the German string really is the
      # one that got rendered.
      expect(I18n.t(:label_filter_child_status_id, :locale => :de).length)
        .to be > I18n.t(:label_filter_child_status_id, :locale => :en).length
    end
  end

  it 'offers no depth above the ceiling' do
    body = settings_page
    options = body[/<select[^>]*id="settings_max_depth".*?<\/select>/m]

    expect(options).not_to be_nil
    values = options.scan(/value="(\d+)"/).flatten.map(&:to_i)
    expect(values).to eq((1..RedmineParentChildFilters::MAX_DEPTH).to_a)
  end
end
