# frozen_string_literal: true

require_relative 'spec_helper'

# Translations drifted silently before: five locales were missing the keys of
# the depth based filters, so those settings rendered as a raw
# "translation missing" string.
RSpec.describe 'translations' do
  PCF_LOCALES_PATH = File.expand_path('../config/locales', __dir__)
  PCF_REFERENCE_KEYS = YAML.load_file(File.join(PCF_LOCALES_PATH, 'en.yml'))['en'].keys.sort.freeze

  Dir[File.join(PCF_LOCALES_PATH, '*.yml')].sort.each do |path|
    locale = File.basename(path, '.yml')

    describe locale do
      let(:translations) { YAML.load_file(path)[locale] }

      it 'is keyed by its own locale' do
        expect(translations).to be_a(Hash)
      end

      it 'covers exactly the keys of the English reference' do
        expect(translations.keys.sort).to eq(PCF_REFERENCE_KEYS)
      end

      it 'has no blank value' do
        expect(translations.reject { |_, v| v.to_s.strip.present? }).to be_empty
      end
    end
  end

  # The settings checkboxes reuse the filter labels, so every enable_<x>_filter
  # setting needs label_filter_<x> and there is no second string to keep in sync.
  it 'resolves every settings label the settings partial renders' do
    keys = Setting.plugin_redmine_parent_child_filters.keys.map do |key|
      if key.start_with?('enable_')
        "label_filter_#{key.delete_prefix('enable_').delete_suffix('_filter')}"
      else
        "label_#{key}"
      end
    end

    Dir[File.join(PCF_LOCALES_PATH, '*.yml')].sort.each do |path|
      locale = File.basename(path, '.yml')
      translations = YAML.load_file(path)[locale]
      expect(keys - translations.keys).to eq([]), "#{locale} is missing settings labels"
    end
  end
end
