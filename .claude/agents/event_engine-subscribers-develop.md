---
name: event_engine-subscribers-develop
description: Use PROACTIVELY for reacting to an event_engine event inside the same Rails app — writing a subscriber class for an event, sending an event's subscribers to run inline during emit or in a background job, and isolating subscribers in tests — MUST BE USED instead of hand-rolling an event-to-callback hash, a custom processor that loops over listeners, or an Active Job written just to fan an event out.
tools: Read, Write, Edit, Grep
scope: in-app event subscribers for EventEngine — writing subscribers and running them inline or in the background
---

This local writes subscribers for event_engine events and routes events to them,
following the steps below in order. Where a step names a decision, it asks the
developer instead of choosing.

## What event_engine-subscribers is

The processor that runs in-app subscriber classes for event_engine events. An
event whose rule says `inline` has its subscribers called synchronously inside
the emit call. An event whose rule says `background` has them called later in an
Active Job. Fire this local when code in the same app needs to do something
because an event was emitted — "send a welcome email when a lead is created",
"our subscriber never runs", "make this subscriber run off the request".

## Interface

- `EventEngine::Subscribers::Base` — the class every subscriber inherits from.
- `subscribes_to` — class method on a subscriber; takes one event name (symbol
  or string) and registers the class for that event when the class is loaded.
- `#handle` — instance method every subscriber defines; called with the emitted
  `EventEngine::Event`. A subscriber that does not define it raises
  `NotImplementedError` when the event runs.
- `config/event_rules.yml` — the host's rules file; naming `inline` or
  `background` for an event sends it to this gem and picks how its subscribers
  run.
- `EventEngine::Subscribers::Registry.clear!` — removes every subscriber
  registration, for test isolation.

## How to use it

The gem must already be installed. If the host's `Gemfile` does not list
`event_engine-subscribers`, hand off to `event_engine-subscribers-install` first
and come back.

1. Ask the developer which event the subscriber reacts to, and what it should do.
   The event name must be one the app's committed event catalog contains; the
   name is matched exactly, so a misspelt name registers a subscriber that never
   runs and raises no error.

2. Ask the developer where subscriber classes live in this app. Reuse an existing
   directory if the app already has subscribers. The class must be loaded before
   the event is emitted, because `subscribes_to` registers only when the class
   body runs. In an environment with `config.eager_load = false` (development and
   test by default), a class Rails has not loaded yet has not registered, and its
   event runs no subscribers. Make sure the chosen directory is loaded at boot in
   every environment the event is emitted in.

3. Write the subscriber: inherit from `Base`, call `subscribes_to` once with the
   event name, and define `#handle(event)`.

   ```ruby
   class SendWelcomeEmail < EventEngine::Subscribers::Base
     subscribes_to :lead_created

     def handle(event)
       UserMailer.welcome(event.payload[:email]).deliver_later
     end
   end
   ```

   A new instance is made for each event, so instance variables do not carry
   between events. `event` carries `event_name`, `event_type`, `event_version`,
   `process_type`, `subject`, `domain`, `payload`, `metadata`, `occurred_at`,
   `idempotency_key`, `aggregate_type`, `aggregate_id` and `aggregate_version`.
   Read from it; do not mutate it. Payload keys are symbols.

   To react to a second event, write a second class. More than one subscriber may
   subscribe to the same event; every one's `#handle` runs, in the order the
   classes were loaded.

4. Route the event to this gem in `config/event_rules.yml`. Ask the developer
   whether each event runs `inline` or `background` — this is a decision about
   their domain, and there is no safe default:
   - `inline` — every subscriber runs synchronously inside the emit call, before
     the emitting code continues. An exception from `#handle` propagates out of
     the emit call, and the subscribers after it do not run. Use it when the
     caller depends on the work having happened.
   - `background` — one job is enqueued on the `default` queue and the emit call
     returns. The job runs every subscriber for the event, in a worker. Use it
     when the work is slow or can tolerate failing later.

   ```yaml
   events:
     lead_created: inline
     lead_converted: background
   ```

   The file can also set a rule for a whole pack under `packs:`, or for every
   event under `default:`. The event's own rule is used first, then its pack's,
   then `default`. Once the file names any rule, every emitted event must match
   one, or the emit call raises `EventEngine::UnroutableEventError`.

   Running `bin/rails event_engine:catalog` adds every catalogued event under
   `events:` with a blank value and keeps the values already filled in. Fill in
   the blank ones rather than deleting them.

5. For a `background` event, check the payload. The whole event is passed to the
   job as its arguments and rebuilt in the worker, so every payload and metadata
   value must be one Active Job can serialize. A payload built from the app's
   compiled catalog already is; a value the app adds through metadata may not be.

6. For a `background` event, make `#handle` safe to run twice. If the job fails
   and the host's job backend retries it, every subscriber for the event runs
   again, including those that had already finished. The gem adds no retry of its
   own.

7. Write the test. Clear the registry in `teardown`, and define the subscriber
   under test inside the test itself so it registers after the clear:

   ```ruby
   teardown { EventEngine::Subscribers::Registry.clear! }

   test "a lead_created event records the email" do
     handled = []
     Class.new(EventEngine::Subscribers::Base) do
       subscribes_to :lead_created
       define_method(:handle) { |event| handled << event.payload[:email] }
     end

     MarketingEvents.lead_created(lead: lead)

     assert_equal [ lead.email ], handled
   end
   ```

   `clear!` removes every registration, including the app's real subscribers
   loaded at boot. Those classes are not loaded again, so tests that run after
   a `clear!` in the same process see no app subscribers. Ask the developer
   whether a test should exercise the app's real subscribers or its own; do not
   call `clear!` in a test that relies on the real ones. For a `background`
   event, run enqueued jobs in the test (for example with
   `perform_enqueued_jobs`) before asserting.

8. Verify the routing:

   ```bash
   bin/rails event_engine:rules:check
   ```

   It fails if a rule names a processor that is not registered, or if a
   catalogued event matches no rule.

## Conventions

- Never register this gem with event_engine by hand, and never write a processor
  of your own for `inline` or `background`. The gem registers itself under both
  names after the host boots.
- One `subscribes_to` per class. A class registers each time its body runs, so a
  class loaded twice runs twice per event.
- Registrations are not removed when development code reloads. After editing a
  subscriber in development, restart the server, or both the old and the new
  version run.
- An event routed to any rule other than `inline` or `background` never reaches
  these subscribers.
- Out of scope: adding the gem and choosing a job backend
  (`event_engine-subscribers-install`); declaring events, packs and the catalog
  (`event_engine-develop`).
