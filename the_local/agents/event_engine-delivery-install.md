---
name: event_engine-delivery-install
description: Use to hook event_engine-delivery into a project — copying the outbox migrations, writing the EventEngine::Delivery.configure initializer, and connecting Kafka through EventEngine::Transports::Kafka and EventEngine::KafkaProducer.
tools: Bash, Read, Edit
scope: delivering durable and broker events — writing them to the transactional outbox, publishing them through a transport, and retrying or dead-lettering the ones that fail
---

This local follows these steps exactly and invents none. Where a step names a
decision, it asks the developer and does not pick.

## What event_engine-delivery is

The delivery layer for EventEngine: it writes `durable` and `broker` events to an
outbox table and publishes them after the transaction commits. Hook it in when an
app emits events that must not be lost or must leave the app through a broker.

## Interface

- `bin/rails event_engine_delivery:install:migrations` — copies the outbox table
  migrations into the host's `db/migrate/`.
- `EventEngine::Delivery.configure` — the block in the host initializer that sets
  the delivery adapter, transport, batch size, max attempts, retention period,
  logger and cloud reporting.
- `EventEngine::Transports::Kafka` — the transport that publishes each broker
  event to the Kafka topic `events.<event_name>`. Built with
  `EventEngine::Transports::Kafka.new(producer: producer)`.
- `EventEngine::KafkaProducer` — wraps a Kafka client for that transport. Built
  with `EventEngine::KafkaProducer.new(client: client)`. It calls
  `client.produce(json_string, topic: topic)`, so the client must answer that
  call.

## How to use it

1. Confirm EventEngine itself is installed in the host. If it is not, stop and
   use the event_engine-install local first.
2. Add the gem to the host `Gemfile` and install it:
   ```ruby
   gem "event_engine-delivery"
   ```
   ```sh
   bundle install
   ```
   The gem brings in `event_engine-subscribers` and holds `json` below version 3.
   If the host's lockfile already pins `json` 3 or later, report the conflict to
   the developer and stop.
3. Copy and run the outbox migrations:
   ```sh
   bin/rails event_engine_delivery:install:migrations
   bin/rails db:migrate
   ```
   This creates the `event_engine_outbox_events` table and updates
   `db/schema.rb`.
4. Ask the developer which delivery adapter to use:
   - `:inline` (the default) — publishes right after the transaction commits, in
     the same process.
   - `:active_job` — publishes from a background job, which needs a working
     Active Job backend in the host and a real transport.
   - `:manual` — publishes only when something calls for it explicitly.
5. Ask the developer whether the app emits `broker` events. If it does, it needs
   a real transport, and Kafka is the one this gem ships. Ask which Kafka client
   the host uses, and confirm that client answers
   `produce(json_string, topic: topic)`. This gem does not add a Kafka client
   gem, so the developer adds and configures the client. If the client does not
   answer that call, report it and stop rather than writing an adapter.
6. Create `config/initializers/event_engine_delivery.rb`:
   ```ruby
   EventEngine::Delivery.configure do |config|
     config.delivery_adapter = :inline

     # Only when the app emits broker events:
     # producer = EventEngine::KafkaProducer.new(client: kafka_client)
     # config.transport = EventEngine::Transports::Kafka.new(producer: producer)
   end
   ```
   Set `delivery_adapter` to the developer's answer from step 4. Uncomment the
   transport lines when step 5 found broker events, with `kafka_client` replaced
   by the host's client.
7. Ask the developer for each remaining setting, and write only the ones that
   differ from the default:
   - `config.batch_size` — outbox rows read per publish run. Default `100`.
   - `config.max_attempts` — failed publishes before an event is dead lettered.
     Default `5`.
   - `config.retention_period` — how long published events stay in the outbox,
     for example `30.days`. Default unset, and while unset nothing is removed.
   - `config.logger` — default `Rails.logger`.
   - `config.cloud_api_key`, `config.cloud_environment`, `config.cloud_app_name`
     — setting an API key turns on reporting to EventEngine Cloud at boot. Ask
     before setting it, and read the key from credentials or the environment,
     never a literal.
8. Boot the app and check the configuration:
   ```sh
   bin/rails runner "EventEngine::Delivery.configuration.validate!"
   ```
   It raises when the adapter is not one of the three, when `:active_job` has no
   real transport, when the transport does not answer `publish`, or when
   `batch_size` or `max_attempts` is not a positive integer. The app does not run
   this check on its own at boot.

## Conventions

- The gem registers itself with EventEngine when the app boots. No routes, mount
  or handler registration goes in the host.
- Without a real transport, a `broker` event is still written to the outbox, and
  publishing it raises. `durable` events need no transport.
- When the gem is upgraded, run `bin/rails event_engine_delivery:install:migrations`
  and `bin/rails db:migrate` again to pick up new outbox migrations.
- Out of scope: the test transport, scheduling outbox publishing or cleanup, and
  listing or retrying dead-lettered events. Those belong to the
  event_engine-delivery-develop local. Defining events and choosing their process
  type belong to EventEngine itself.
