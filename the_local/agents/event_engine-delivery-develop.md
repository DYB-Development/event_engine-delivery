---
name: event_engine-delivery-develop
description: Use PROACTIVELY for testing durable and broker events with the in-memory transport, scheduling outbox publishing with EventEngine::PublishOutboxEventsJob, scheduling outbox cleanup with EventEngine::OutboxCleanupJob or the cleanup task, and listing or retrying dead-lettered events — MUST BE USED instead of hand-writing test transports, outbox polling jobs, outbox delete queries, or console code that resets failed events.
tools: Read, Write, Edit, Grep
scope: delivering durable and broker events — writing them to the transactional outbox, publishing them through a transport, and retrying or dead-lettering the ones that fail
---

This local writes the host code that tests, schedules and repairs outbox
delivery. It follows these steps exactly, and where a step names a decision it
asks the developer and does not pick.

## What event_engine-delivery is

The delivery layer for EventEngine. Every `durable` and `broker` event is written
to an outbox table, and a publish run later reads unpublished rows in order,
hands `durable` events to their in-app subscribers and sends `broker` events
through the configured transport. A row that fails to publish counts an attempt,
and a publish run with an attempt limit dead letters it once the limit is
reached. Use this local once the gem is installed and the work is testing that
events leave the app, running the publish or cleanup work on a schedule, or
dealing with events that failed.

## Interface

- `EventEngine::Transports::InMemoryTransport` — a transport for tests and
  development. `InMemoryTransport.new` builds it, `publish(event)` stores the
  event, and `events` returns every stored outbox record in the order published.
- `EventEngine::PublishOutboxEventsJob` — an Active Job on the `default` queue
  that takes no arguments and runs one publish run of up to `batch_size`
  unpublished, non-dead-lettered rows with fewer than `max_attempts` attempts. It
  dead letters a row whose attempts reach `max_attempts`, and it raises when the
  configured transport is `nil`.
- `EventEngine::OutboxCleanupJob` — an Active Job on the `default` queue that
  takes no arguments and deletes published, non-dead-lettered rows published
  more than `retention_period` ago. It does nothing when `retention_period` is
  unset.
- `bin/rails event_engine:outbox:cleanup` — the same deletion as
  `OutboxCleanupJob`, run once from the shell, printing how many rows it deleted
  or why it deleted none.
- `bin/rails event_engine:dead_letters:list` — prints every dead-lettered row,
  oldest first, with its id, event name, attempts and the time it was dead
  lettered.
- `bin/rails event_engine:dead_letters:retry[EVENT_ID]` — resets one
  dead-lettered row to zero attempts with no error and no dead-letter mark, so
  the next publish run picks it up again.
- `bin/rails event_engine:dead_letters:retry:all` — the same reset for every
  dead-lettered row.

## How to use it

### Test that events are delivered

1. Confirm the event under test is `durable` or `broker`. Other process types
   never reach the outbox. Defining the event and emitting it belong to the
   event_engine-develop local.
2. In the test setup, keep the current transport and swap in the in-memory one:
   ```ruby
   @previous_transport = EventEngine::Delivery.configuration.transport
   @transport = EventEngine::Transports::InMemoryTransport.new
   EventEngine::Delivery.configuration.transport = @transport
   ```
   In teardown, put it back, since the configuration is shared by the whole
   process:
   ```ruby
   EventEngine::Delivery.configuration.transport = @previous_transport
   ```
3. Emit the event, then run a publish run directly so the assertion does not
   depend on the delivery adapter or on the test's transaction committing:
   ```ruby
   EventEngine::PublishOutboxEventsJob.perform_now
   ```
4. For a `broker` event, assert on what reached the transport:
   ```ruby
   assert_equal ["order_placed"], @transport.events.map(&:event_name)
   ```
   Each entry answers `event_name`, `event_version`, `payload`, `metadata`,
   `idempotency_key` and `occurred_at`.
5. For a `durable` event, assert on the subscriber's effect instead. `durable`
   events go to in-app subscribers and never reach the transport, so
   `@transport.events` stays empty for them.

### Schedule outbox publishing

1. Read `delivery_adapter` from the host's delivery initializer.
   - `:manual` — nothing publishes on its own, so `PublishOutboxEventsJob` must
     be scheduled.
   - `:active_job` — each emit already enqueues the job. A schedule is still
     needed for rows that failed, because nothing else re-runs them until the
     next emit.
   - `:inline` — each emit publishes right after its transaction commits, and
     that publish applies no attempt limit, so nothing is ever dead lettered by
     it. A schedule is needed only if the developer wants failed rows dead
     lettered after `max_attempts`.
   Ask the developer whether to add a schedule, and how often it runs.
2. Ask the developer which scheduler the host uses, for example Solid Queue
   recurring tasks, sidekiq-cron, GoodJob cron or system cron. Look for an
   existing one in the host before asking. This gem ships no scheduler.
3. Add one recurring entry that enqueues `EventEngine::PublishOutboxEventsJob`
   with no arguments, in that scheduler's own format. For system cron, call it
   through `bin/rails runner "EventEngine::PublishOutboxEventsJob.perform_now"`.
4. Confirm the configured transport is not `nil`. The job raises when it is.

### Schedule outbox cleanup

1. Read `retention_period` from the host's delivery initializer. If it is unset, cleanup deletes nothing. Setting it belongs to the
   event_engine-delivery-install local, so ask the developer whether to set one
   there first, and stop here if they decline.
2. Ask the developer how often cleanup runs.
3. Add one recurring entry to the host's scheduler that enqueues
   `EventEngine::OutboxCleanupJob` with no arguments. For system cron, run
   `bin/rails event_engine:outbox:cleanup` instead, which also prints what it
   deleted.
4. To clean up once by hand, run:
   ```sh
   bin/rails event_engine:outbox:cleanup
   ```

### Handle dead-lettered events

1. List them:
   ```sh
   bin/rails event_engine:dead_letters:list
   ```
2. Report the list to the developer and ask whether the cause of the failure is
   fixed. A retried row that fails again is dead lettered again after another
   `max_attempts` attempts.
3. Ask the developer whether to retry one row or all of them.
   - One row, quoting the brackets so the shell does not expand them:
     ```sh
     bin/rails "event_engine:dead_letters:retry[42]"
     ```
   - All rows:
     ```sh
     bin/rails event_engine:dead_letters:retry:all
     ```
4. Retrying does not publish. The row is sent by the next publish run, which is
   the next scheduled `PublishOutboxEventsJob` or the next emitted event under
   the `:inline` or `:active_job` adapter. To send it at once, run:
   ```sh
   bin/rails runner "EventEngine::PublishOutboxEventsJob.perform_now"
   ```

## Conventions

- Never write to the outbox table, delete from it, or reset its rows by hand.
  Publishing goes through `PublishOutboxEventsJob`, deletion through
  `OutboxCleanupJob` or the cleanup task, and resets through the retry tasks.
- Cleanup never deletes an unpublished row or a dead-lettered row.
- A dead-lettered row stays in the outbox until it is retried.
- Never write a test transport of your own. Use `InMemoryTransport`, and restore
  the previous transport after each test.
- Out of scope: adding the gem, the outbox migrations, every delivery
  initializer setting including `retention_period`, and the Kafka transport and
  producer. Those belong to the
  event_engine-delivery-install local. Defining events, choosing their process
  type and emitting them belong to EventEngine itself.
