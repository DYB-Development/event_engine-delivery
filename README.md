# EventEngine::Delivery

The **delivery layer** for [EventEngine](https://github.com/tylercschneider/event_engine).

`event_engine` (the core) declares events with a schema-first DSL, compiles them to
a committed schema, and **dispatches** built events to registered handlers. It does
not deliver anything on its own. `event_engine-delivery` is the processor that takes an
emitted event and **gets it delivered reliably**:

- the durability **level ladder** (1 sync → 2 job → 3 outbox → 4 broker),
- a transactional **outbox** (`event_engine_outbox_events`),
- **retries** and **dead-letter** handling,
- pluggable **transports** (in-memory, Kafka, or your own),
- an observability **dashboard**,
- an optional **cloud reporter**.

Apps that only need to *declare* events depend on `event_engine` alone. Add this gem
when you need durable, reliable delivery.

> **Namespacing note (transitional).** This gem is being extracted from `event_engine`
> via copy-then-subtract. Most of its classes still live under the top-level
> `EventEngine::` namespace (e.g. `EventEngine::Transports::Kafka`,
> `EventEngine::OutboxEvent`, `EventEngine::OutboxPublisher`). The delivery-specific
> entry points are `EventEngine::Delivery` (config, engine, processor). The examples
> below use the namespaces as they exist today.

---

## Table of contents

- [Installation](#installation)
- [How it hooks into the core](#how-it-hooks-into-the-core)
- [Level routing](#level-routing)
- [The outbox table](#the-outbox-table)
- [Configuration](#configuration)
- [Delivery adapters](#delivery-adapters)
- [Transports](#transports)
  - [Writing a custom transport](#writing-a-custom-transport)
  - [Customizing Kafka topics / payloads](#customizing-kafka-topics--payloads)
- [Idempotency](#idempotency)
- [Dead-letter recovery](#dead-letter-recovery)
- [Outbox cleanup](#outbox-cleanup)
- [Instrumentation](#instrumentation)
- [Dashboard](#dashboard)
- [Cloud reporter](#cloud-reporter)
- [Customization recipes](#customization-recipes)
- [License](#license)

---

## Installation

```ruby
# Gemfile
gem "event_engine"
gem "event_engine-delivery"
```

```bash
bundle install
```

Install the outbox migration and run it:

```bash
bin/rails event_engine:install:migrations   # copies the outbox migrations into your app
bin/rails db:migrate
```

Then add an initializer:

```ruby
# config/initializers/event_engine_delivery.rb
EventEngine::Delivery.configure do |config|
  config.delivery_adapter = :inline   # :inline | :active_job | :manual
  config.transport        = EventEngine::Transports::InMemoryTransport.new
  config.batch_size       = 100
  config.max_attempts     = 5
end
```

> **Configure delivery via `EventEngine::Delivery.configure`.** Delivery options
> (`delivery_adapter`, `transport`, …) live on `EventEngine::Delivery::Configuration`.
> The core `EventEngine.configure` only knows about `logger`.

---

## How it hooks into the core

At Rails boot, the delivery engine registers itself with the core as the processor
for the `durable` and `broker` process types:

```ruby
# lib/event_engine/delivery/engine.rb
initializer "event_engine.delivery.register_processor" do
  config.after_initialize do
    processor = Processor.new
    Processor::PROCESS_TYPES.each { |process_type| EventEngine.register_processor(process_type, processor) }
    Engine.send(:start_cloud_reporter!)
  end
end
```

The host's rules file decides which events take those roads, for example
`quote_signed: durable`. `inline` and `background` events are processed by
`event_engine-subscribers` and never reach this gem.

---

## Process type routing

`EventEngine::Delivery::Processor#call` writes the event to the outbox, fires
`event_engine.event_emitted`, and triggers publishing per the configured
[delivery adapter](#delivery-adapters). When the outbox drains,
`EventEngine::OutboxRouter` routes by process type:

- **durable** → invokes the event's in-app subscribers. No transport is needed.
- **broker** → publishes to the configured **transport**, raising
  `MissingTransportError` if none is configured.
- **sourced** → raises `UnsupportedProcessTypeError`.

---

## The outbox table

Events at level 3+ are persisted to `event_engine_outbox_events` before delivery, so
they survive a crash and are written atomically with your transaction. The
`EventEngine::OutboxEvent` model is **append-only for its core fields**
(`attr_readonly`), with these columns:

| Column | Type | Notes |
|---|---|---|
| `event_name` | string | NOT NULL |
| `event_type` | string | NOT NULL |
| `event_version` | integer | NOT NULL |
| `payload` | json | NOT NULL |
| `metadata` | json | optional context |
| `idempotency_key` | string | **unique index** |
| `occurred_at` | datetime | NOT NULL |
| `published_at` | datetime | set when delivered |
| `dead_lettered_at` | datetime | set when attempts exhausted |
| `attempts` | integer | default 0 |
| `last_error_message` | text | last failure message |
| `last_error_class` | string | last failure class |
| `aggregate_type` / `aggregate_id` / `aggregate_version` | string / string / integer | aggregate tracking |
| `event_level` | integer | the dispatched level |
| `created_at` / `updated_at` | datetime | standard |

Useful scopes and methods:

```ruby
OutboxEvent.unpublished        # published_at IS NULL
OutboxEvent.active             # not dead-lettered
OutboxEvent.dead_lettered      # dead_lettered_at IS NOT NULL
OutboxEvent.retryable(max)     # attempts < max
OutboxEvent.cleanable          # published and not dead-lettered
OutboxEvent.for_aggregate(t,i) # ordered events for an aggregate

event.retry!          # reset attempts + clear dead-letter + clear last_error
event.dead_letter!    # mark dead-lettered now
event.mark_published! # stamp published_at
OutboxEvent.next_aggregate_version(type, id)
```

---

## Configuration

All on `EventEngine::Delivery.configure`:

| Option | Default | Purpose |
|---|---|---|
| `delivery_adapter` | `:inline` | `:inline`, `:active_job`, or `:manual` |
| `transport` | `NullTransport` | Object responding to `#publish(event)` |
| `batch_size` | `100` | Max events per `OutboxPublisher` batch |
| `max_attempts` | `5` | Publish attempts before dead-lettering |
| `retention_period` | `nil` | Age after which published events are cleanable (`nil` = keep) |
| `dashboard_auth` | `nil` | Callable `->(controller) { bool }` gating the dashboard |
| `logger` | `Rails.logger` | Where delivery logs |
| `cloud_api_key` | `nil` | Enables the cloud reporter when set |
| `cloud_endpoint` | `https://api.eventengine.dev/v1/ingest` | Cloud ingest URL |
| `cloud_environment` | `nil` | Environment label |
| `cloud_app_name` | `nil` | App label |
| `cloud_batch_size` | `50` | Cloud entries per flush |
| `cloud_flush_interval` | `10` | Seconds between cloud flushes |

`EventEngine::Delivery::Configuration#validate!` enforces the invariants you'd want:
`delivery_adapter` must be one of `:inline/:active_job/:manual`; `:active_job`
requires a real transport (not `NullTransport`); a transport must respond to
`#publish`; `batch_size`/`max_attempts` must be positive integers. It raises
`InvalidConfigurationError` otherwise.

---

## Delivery adapters

`delivery_adapter` decides *when* the outbox is drained after a level-3+ write:

- **`:inline`** (default) — drains in-process. Inside an open transaction it
  registers an after-commit callback (so publishing happens only once your data is
  committed); outside a transaction it publishes immediately. Great for monoliths and
  tests.
- **`:active_job`** — enqueues `EventEngine::PublishOutboxEventsJob`, which runs
  `OutboxPublisher`. Use this in production so request latency isn't tied to delivery.
  Requires a real transport (validated).
- **`:manual`** — does nothing automatically. You drain the outbox yourself — a cron
  job, a rake task, or an operator action calling `OutboxPublisher`. Choose this when
  you want full control over publish timing (e.g. batch windows, maintenance pauses).

Draining manually:

```ruby
EventEngine::OutboxPublisher.new(
  router:      EventEngine::OutboxRouter.new(transport: EventEngine::Delivery.configuration.transport),
  batch_size:  EventEngine::Delivery.configuration.batch_size,
  max_attempts: EventEngine::Delivery.configuration.max_attempts
).call
```

---

## Transports

A transport is any object that responds to `publish(event)` and raises on failure
(so the publisher can retry). Three ship with the gem:

| Transport | Use |
|---|---|
| `EventEngine::Transports::NullTransport` | Default. Logs a warning and discards. Counts as "no transport" for level-4 checks. |
| `EventEngine::Transports::InMemoryTransport` | Dev/test. Collects events in `#events` for assertions. |
| `EventEngine::Transports::Kafka` | Production. Wraps a producer; publishes to topics `events.{event_name}`. |

```ruby
# dev/test
config.transport = EventEngine::Transports::InMemoryTransport.new

# Kafka — you bring the client; EventEngine never manages Kafka
kafka    = Kafka.new(seed_brokers: ENV["KAFKA_BROKERS"])
producer = EventEngine::KafkaProducer.new(client: kafka)
config.transport = EventEngine::Transports::Kafka.new(producer: producer)
```

### Writing a custom transport

The contract is one method. Raise on failure to trigger retry/dead-lettering.

```ruby
class SqsTransport
  def initialize(client:, queue_url:)
    @client = client
    @queue_url = queue_url
  end

  # `event` is the persisted EventEngine::OutboxEvent. It exposes:
  #   event_name, event_type, event_version, idempotency_key,
  #   payload, metadata, occurred_at, aggregate_type/id/version
  def publish(event)
    @client.send_message(
      queue_url: @queue_url,
      message_body: JSON.generate(
        name:    event.event_name,
        version: event.event_version,
        key:     event.idempotency_key,
        payload: event.payload,
        meta:    event.metadata
      )
    )
    # raise on a non-success response so it retries
  end
end

EventEngine::Delivery.configure { |c| c.transport = SqsTransport.new(client: sqs, queue_url: url) }
```

**Why** a custom transport: target a broker EventEngine doesn't ship (SQS, SNS,
RabbitMQ, Redis Streams, an internal HTTP bus), add tracing/headers, or fan out to
multiple destinations from one `publish`.

### Customizing Kafka topics / payloads

The built-in Kafka transport hardcodes the topic as `events.{event_name}` and a
fixed JSON shape. To change either (e.g. environment-namespaced topics like
`prod.events.cow_fed`, a partition key, or a different envelope), write a thin
transport instead of using the built-in one:

```ruby
class NamespacedKafka
  def initialize(producer:, prefix: Rails.env)
    @producer = producer
    @prefix = prefix
  end

  def publish(event)
    topic = "#{@prefix}.events.#{event.event_name}"
    @producer.publish(topic, envelope(event), key: event.aggregate_id)
  end

  private

  def envelope(event)
    { name: event.event_name, version: event.event_version,
      key: event.idempotency_key, payload: event.payload,
      occurred_at: event.occurred_at }
  end
end
```

**Why:** a shared Kafka cluster across environments needs topic namespacing to avoid
cross-environment contamination; ordered consumers need a deterministic partition
key (usually the aggregate id).

---

## Idempotency

Every outbox event has an `idempotency_key` — an auto-generated UUID, or one you
supply at emit time:

```ruby
EventEngine.cow_fed(cow: cow, idempotency_key: "cow-#{cow.id}-fed-#{Date.current}")
```

- The column has a **unique index**, so the same logical event can't be written
  twice.
- The key is passed through to transports so **consumers can deduplicate**.
- EventEngine stores and transmits the key but does **not** enforce idempotent
  *processing* downstream — consumers must dedupe on their end.

Override the auto-UUID when you want domain-level dedup (one feed per cow per day),
to make user-action retries safe, or to correlate across systems.

---

## Dead-letter recovery

After `max_attempts` failed publishes, an event is dead-lettered (its
`dead_lettered_at`, `last_error_message`, and `last_error_class` are set).

```bash
bin/rails event_engine:dead_letters:list        # list dead-lettered events
bin/rails event_engine:dead_letters:retry[123]  # retry one by id
bin/rails event_engine:dead_letters:retry:all   # retry every dead-lettered event
```

Programmatically:

```ruby
event = EventEngine::OutboxEvent.dead_lettered.find(123)
event.retry!   # attempts → 0, dead_lettered_at → nil, last_error_* cleared
```

Typical loop: `dead_letters:list` → diagnose via `last_error_*` → fix the cause →
`dead_letters:retry:all`.

---

## Outbox cleanup

Published events accumulate. Configure a retention window and the cleaner deletes
**only** events that are both published and not dead-lettered:

```ruby
config.retention_period = 30.days   # nil disables cleanup entirely
```

```bash
bin/rails event_engine:outbox:cleanup
```

Or schedule `EventEngine::OutboxCleanupJob` (it no-ops when `retention_period` is
nil):

```ruby
# e.g. sidekiq-cron
Sidekiq::Cron::Job.create(name: "EventEngine cleanup", cron: "0 3 * * *",
                          class: "EventEngine::OutboxCleanupJob")
```

---

## Instrumentation

Delivery emits `ActiveSupport::Notifications` you can subscribe to for APM/logging:

| Notification | When | Key payload |
|---|---|---|
| `event_engine.event_emitted` | written to outbox | `event_name`, `event_version`, `event_id`, `idempotency_key`, `aggregate_*` |
| `event_engine.event_published` | sent to transport | `event_name`, `event_version`, `event_id` |
| `event_engine.event_dead_lettered` | attempts exhausted | `+ attempts`, `error_message`, `error_class` |
| `event_engine.publish_batch` | a publish batch finished | `count` |

```ruby
ActiveSupport::Notifications.subscribe("event_engine.event_dead_lettered") do |*, payload|
  Alerting.notify("Dead-lettered #{payload[:event_name]} after #{payload[:attempts]} attempts")
end
```

---

## Dashboard

A small observability UI for the outbox.

```ruby
# config/initializers/event_engine_delivery.rb
EventEngine::Delivery.configure do |config|
  config.dashboard_auth = ->(controller) { controller.current_user&.admin? }
end
```

```ruby
# config/routes.rb
mount EventEngine::Delivery::Engine => "/event_engine", as: :event_engine
```

Then visit `/event_engine/dashboard`:

- **Overview** — totals (all / published / unpublished / dead-lettered).
- **Events** — paginated list (20/page) with status, plus a detail view of payload &
  metadata.
- **Dead letters** — list with single and bulk **retry** buttons.

Access is gated by `dashboard_auth`. If it's `nil` or returns false, the dashboard
returns **403 Forbidden** (and logs a warning when unconfigured). The gem ships
functional but unstyled HTML — bring your own CSS if you want it pretty.

> Mount **`EventEngine::Delivery::Engine`** (this gem), not `EventEngine::Engine`
> (core). The dashboard controllers live here.

---

## Cloud reporter

Optionally stream lightweight **metadata** (never payloads or business data) to
EventEngine Cloud for real-time observability.

```ruby
config.cloud_api_key = ENV["EVENT_ENGINE_CLOUD_KEY"]
```

That's it — the reporter starts at boot when a key is present, and is a zero-overhead
no-op when absent. It hooks the same `ActiveSupport::Notifications` above, batches
entries (`cloud_batch_size`, default 50), and flushes on a timer
(`cloud_flush_interval`, default 10s). What's sent: event name, type, version,
status (emitted/published/dead-lettered), timestamps, attempt counts, and error
classes for dead letters.

**Failure isolation:** all calls are fire-and-forget with a 5s timeout over
`Net::HTTP`; errors are logged, never raised — the reporter can never affect your
app.

---

## Customization recipes

**Run delivery and a durable log together.** Add `event_engine-store`. Delivery
processes `durable` and `broker` events, and the store's handlers record every
event whatever its process type.

**Pause delivery during maintenance.** Set `delivery_adapter = :manual`; events keep
landing in the outbox safely and you drain them with `OutboxPublisher` when ready.

**Different transports per destination.** Write one transport whose `publish`
fans out to several brokers, or branch on `event.event_type` / `event.event_name`
inside `publish`.

**Tune durability per event.** Change `event_level` in the definition (1→2→3→4). No
producer code changes; re-dump the schema (level isn't fingerprinted, so it won't
bump the version).

---

## License

Available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
