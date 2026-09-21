source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Specify your gem's dependencies in event_engine-delivery.gemspec.
gemspec

# The core gem this delivery layer builds on. Use the local checkout when it's
# present (development); fall back to the GitHub source on CI, where the sibling
# repo isn't checked out.
event_engine_path = File.expand_path("../event_engine", __dir__)
if File.directory?(event_engine_path)
  gem "event_engine", path: event_engine_path
else
  gem "event_engine", github: "tylercschneider/event_engine"
end

# The event definition gem owns EventDefinition, which the schema rake tasks
# read. Same local/CI resolution as core.
event_engine_event_definition_path = File.expand_path("../event_engine-event_definition", __dir__)
if File.directory?(event_engine_event_definition_path)
  gem "event_engine-event_definition", path: event_engine_event_definition_path
else
  gem "event_engine-event_definition", github: "DYB-Development/event_engine-event_definition"
end

# The subscribers gem owns subscriber execution (:inline/:background) and the
# Subscriber API the :durable drain calls. Same local/CI resolution as core.
event_engine_subscribers_path = File.expand_path("../event_engine-subscribers", __dir__)
if File.directory?(event_engine_subscribers_path)
  gem "event_engine-subscribers", path: event_engine_subscribers_path
else
  gem "event_engine-subscribers", github: "tylercschneider/event_engine-subscribers"
end

gem "the_local", github: "tylercschneider/the_local"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

group :development, :test do
  # Needed for the dummy app database
  gem "sqlite3"
  gem "sprockets-rails"
  gem "pry"
  gem "pry-byebug"
  gem "minitest", "~> 5.0"  # pin to 5.x; minitest 6 removed minitest/mock
  gem "minitest-reporters"
  gem "minitest-focus"
  gem "diffy"
  gem "webmock"
end
