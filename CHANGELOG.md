# Changelog

All notable changes to this project are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Delivery registers itself as the processor for the `durable` and `broker` process
  types, in place of a handler registered for every event. An event reaches the
  outbox only when the host's rules route it to `durable` or `broker`.
- A `durable` event is delivered to its subscribers when no transport is configured.

### Added
- Initial gem scaffold: mountable `EventEngine::Delivery` Rails engine depending on
  `event_engine`.
- Verbatim copy of `event_engine` as the starting point for the delivery layer
  (standalone, depends only on Rails); full suite green. Inherited RuboCop offenses
  grandfathered in `.rubocop_todo.yml` so the lint gate still checks new code.

### Changed
- Connected to `event_engine` core: deleted the duplicated core files (definitions,
  schema, registry, `Event`, `EventBuilder`, subscribers, etc.) and now depend on the
  `event_engine` gem for them. Delivery registers its pipeline as a handler via the new
  `EventEngine::Delivery::Handler` (built `Event` → level 1 subscribers / 2 job / 3+
  outbox+transport). Delivery configuration moved to `EventEngine::Delivery.configure`
  (`transport`, `delivery_adapter`, `batch_size`, `retention_period`, `cloud_*`). The
  dashboard mounts on `EventEngine::Delivery::Engine`.
