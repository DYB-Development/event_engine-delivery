---
name: event_engine-delivery-info
description: Use to learn what event_engine-delivery offers — the transactional outbox, durable and broker events, transports, retries, dead letters, and outbox retention.
tools: Read
scope: delivering durable and broker events — writing them to the transactional outbox, publishing them through a transport, and retrying or dead-lettering the ones that fail
---

This local explains event_engine-delivery and makes no changes.

## What event_engine-delivery is

event_engine-delivery is the delivery layer for EventEngine. EventEngine defines
and emits events, and each event carries a process type. This gem handles the
two process types that must not be lost: `durable` and `broker`. It writes each
such event to an outbox table in the same database transaction as the change
that caused it. It then publishes the event once that transaction commits.

Reach for it when an event has to survive a crash or a rolled-back request, or
when an event has to leave the app through a message broker. Events with the
`inline` or `background` process type are not handled here. event_engine-subscribers
runs those.

## Interface

This local declares no commands. The other two locals own the whole surface:

- **event_engine-delivery-install** owns adding the gem to an app. That covers
  the outbox migrations, the initializer settings, and connecting a real broker
  transport.
- **event_engine-delivery-develop** owns working with the gem once it is
  installed. That covers the test transport, the jobs that publish and clean up
  the outbox, and the tasks that list and retry dead-lettered events.

## How to use it

- The gem is not in the app yet, or the app needs a broker connection: use the
  install local.
- The gem is installed and you are writing tests, scheduling outbox work, or
  handling failed events: use the develop local.
- You are defining an event or choosing its process type: that belongs to
  EventEngine itself, not this gem.

## Conventions

- **Outbox** — the table every durable and broker event is written to before it
  is published. A row stays there after publishing until retention removes it.
- **`durable`** — an event written to the outbox and then handed to its
  subscribers inside the app. It needs no broker.
- **`broker`** — an event written to the outbox and then published through the
  transport. Publishing raises an error when no real transport is configured.
- **`sourced`** — a process type for event sourcing. This gem does not support
  it and raises an error when one is routed.
- **Transport** — the object that sends a broker event out of the app. Any
  object that responds to `publish(event)` qualifies. The default transport
  publishes nothing. A Kafka transport ships with the gem and names topics
  `events.<event_name>`.
- **Delivery adapter** — when the outbox gets published. `inline` publishes
  right after the transaction commits. `active_job` publishes from a background
  job and requires a real transport. `manual` publishes only when something
  calls for it explicitly.
- **Batch size** — how many outbox rows one publish run reads. The default is
  100.
- **Max attempts** — how many failed publishes an event gets before it is dead
  lettered. The default is 5. It applies when the outbox is published by the
  background job. An `inline` publish applies no attempt limit.
- **Dead letter** — an event that ran out of attempts. It stays in the outbox,
  marked dead lettered, until someone retries it.
- **Retention period** — how long a published event stays in the outbox. It is
  unset by default, and while it is unset nothing is cleaned up.
