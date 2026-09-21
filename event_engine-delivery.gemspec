require_relative "lib/event_engine/delivery/version"

Gem::Specification.new do |spec|
  spec.name        = "event_engine-delivery"
  spec.version     = EventEngine::Delivery::VERSION
  spec.authors     = [ "tylercschneider" ]
  spec.email       = [ "tylercschneider@gmail.com" ]
  spec.homepage    = "https://github.com/tylercschneider/event_engine-delivery"
  spec.summary     = "Reliable event delivery for EventEngine"
  spec.description = "The delivery layer for EventEngine: the durability level ladder (0-4), transactional outbox, retry, dead-letter handling, and pluggable transports. Depends on event_engine for event definitions and schema."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/tylercschneider/event_engine-delivery/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/tylercschneider/event_engine-delivery/issues"
  spec.metadata["documentation_uri"] = "https://github.com/tylercschneider/event_engine-delivery#readme"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  spec.add_dependency "rails", ">= 7.1.6", "< 9"
  spec.add_dependency "event_engine"
  spec.add_dependency "event_engine-subscribers"
  spec.add_dependency "event_engine-event_definition"
end
