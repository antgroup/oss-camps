#!/usr/bin/env ruby

require "yaml"

ROOT = File.expand_path("..", __dir__)
FORM_PATTERN = File.join(ROOT, ".github", "ISSUE_TEMPLATE", "camp-*.yml")
FORM_PAIRS = [
  ["camp-low-difficulty.yml", "camp-low-difficulty-en.yml"],
  ["camp-medium-high-difficulty.yml", "camp-medium-high-difficulty-en.yml"]
].freeze
ALLOWED_COMPONENTS = %w[markdown input textarea dropdown checkboxes].freeze
REQUIRED_FORM_KEYS = %w[name description title labels body].freeze

errors = []
forms = Dir.glob(FORM_PATTERN).sort
parsed_forms = {}

errors << "No camp Issue Forms found" if forms.empty?

yaml_pattern = File.join(ROOT, "**", "*.{yml,yaml}")
Dir.glob(yaml_pattern, File::FNM_DOTMATCH).sort.each do |path|
  relative_path = path.delete_prefix("#{ROOT}/")

  begin
    YAML.safe_load(File.read(path), aliases: false)
  rescue Psych::SyntaxError => error
    errors << "#{relative_path}: invalid YAML (#{error.message})"
  end
end

forms.each do |path|
  relative_path = path.delete_prefix("#{ROOT}/")

  begin
    form = YAML.safe_load(File.read(path), aliases: false)
  rescue Psych::SyntaxError => error
    errors << "#{relative_path}: invalid YAML (#{error.message})"
    next
  end

  parsed_forms[File.basename(path)] = form

  missing_keys = REQUIRED_FORM_KEYS.reject { |key| form.key?(key) }
  errors << "#{relative_path}: missing keys: #{missing_keys.join(', ')}" unless missing_keys.empty?

  body = form["body"]
  unless body.is_a?(Array) && !body.empty?
    errors << "#{relative_path}: body must be a non-empty array"
    next
  end

  ids = []
  body.each_with_index do |component, index|
    location = "#{relative_path}: body item #{index + 1}"
    type = component["type"]
    errors << "#{location} has unsupported type: #{type.inspect}" unless ALLOWED_COMPONENTS.include?(type)

    next if type == "markdown"

    id = component["id"]
    errors << "#{location} must have an id" if id.to_s.empty?
    errors << "#{location} has an invalid id: #{id.inspect}" unless id.to_s.match?(/\A[A-Za-z0-9_-]+\z/)
    errors << "#{location} must have a label" if component.dig("attributes", "label").to_s.empty?
    ids << id unless id.to_s.empty?
  end

  id_counts = ids.each_with_object(Hash.new(0)) { |id, counts| counts[id] += 1 }
  duplicate_ids = id_counts.select { |_id, count| count > 1 }.keys
  errors << "#{relative_path}: duplicate ids: #{duplicate_ids.join(', ')}" unless duplicate_ids.empty?
end

FORM_PAIRS.each do |chinese_name, english_name|
  chinese_form = parsed_forms[chinese_name]
  english_form = parsed_forms[english_name]
  next unless chinese_form && english_form

  signature = lambda do |form|
    components = form.fetch("body").map do |component|
      [component["type"], component["id"], component.dig("validations", "required") == true]
    end
    [form["labels"], components]
  end

  unless signature.call(chinese_form) == signature.call(english_form)
    errors << "#{chinese_name} and #{english_name}: labels or field structures do not match"
  end
end

Dir.glob(File.join(ROOT, "**", "*.md"), File::FNM_DOTMATCH).sort.each do |path|
  relative_path = path.delete_prefix("#{ROOT}/")
  content = File.binread(path)
  errors << "#{relative_path}: file must end with one newline" unless content.end_with?("\n") && !content.end_with?("\n\n")
end

if errors.empty?
  puts "Validated #{forms.length} Issue Forms, all YAML, and all Markdown files."
  exit 0
end

warn errors.map { |error| "- #{error}" }.join("\n")
exit 1
