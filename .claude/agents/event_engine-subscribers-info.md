---
name: event_engine-subscribers-info
description: Use to learn what event_engine-subscribers offers — in-app subscribers for EventEngine events, and running them inline or in a background job.
tools: Read
scope: in-app event subscribers for EventEngine — writing subscribers and running them inline or in the background
---

This local explains event_engine-subscribers and the words it uses. It changes
nothing and gives no steps. Read it to orient, then go to the local that owns the
work.

## What event_engine-subscribers is

event_engine-subscribers is the subscriber layer for event_engine. event_engine
checks an emitted event against its catalog and routes it to one processor by the
event's process type. This gem is that processor for two process types, `inline`
and `background`. It registers itself with event_engine once the host app has
finished booting, so there is nothing to wire by hand.

Reach for it when code inside the same Rails app needs to react to an event:
send an email when a user registers, update a counter when an order ships. For an
`inline` event, every subscriber runs in the same process before the emit call
returns. For a `background` event, one job is enqueued and the subscribers run in
the worker that picks it up. Events on the other process types — `durable`,
`broker`, `telemetry`, `sourced` — are not handled here.

## Interface

This local documents no commands. It is background only.

The `event_engine-subscribers-install` local owns adding the gem to a host app.
The `event_engine-subscribers-develop` local owns writing subscribers, choosing
which process type an event runs on, and keeping subscribers isolated between
tests. Everything you would call, declare or edit lives in one of those two.

## How to use it

One decision: are you adding the gem to an app, or writing subscribers in an app
that already has it?

- Adding the gem to a host app → `event_engine-subscribers-install`.
- Writing a subscriber, sending an event inline or to the background, or testing
  subscribers → `event_engine-subscribers-develop`.

Events, the catalog, processors and routing belong to event_engine itself. For
those, go to `event_engine-info`, `event_engine-install` or
`event_engine-develop`.

If you only needed the vocabulary, you have it. Stop here.

## Conventions

- **Subscriber** — a class in the host app that reacts to one event. It is
  matched by event name alone, not by domain or version. One event may have many
  subscribers, and they run in the order their classes were loaded.
- **Registration at load** — a subscriber registers itself when its class is
  loaded. A subscriber whose class has not been loaded does not run, which
  matters in an app that loads code lazily.
- **One instance per event** — each subscriber is instantiated fresh for every
  event it receives, so it keeps no state between events.
- **Inline** — subscribers run synchronously in the emitting process. An error
  raised by one reaches the code that emitted the event, and the subscribers
  after it do not run.
- **Background** — the event is enqueued as one job on the `default` queue. The
  job rebuilds the event from its attributes and runs every subscriber in the
  worker. The gem sets no retry of its own, so a failure is left to the app's
  queue backend.
- **Process type** — decided by event_engine from the event's rule, never by the
  subscriber. The same subscriber runs inline or in the background depending on
  which the event names.
