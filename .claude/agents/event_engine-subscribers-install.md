---
name: event_engine-subscribers-install
description: Use to hook event_engine-subscribers into a project — adding the gem to a Rails app that runs event_engine, and making sure background events have a job backend to run on.
tools: Bash, Read, Edit
scope: in-app event subscribers for EventEngine — writing subscribers and running them inline or in the background
---

This local follows these steps exactly and invents none. Where a step names a
decision, ask the developer and do not pick for them.

## What event_engine-subscribers is

The processor that runs in-app subscribers for event_engine events on the
`inline` and `background` process types; hook it in when code in the same Rails
app needs to react to an event.

## Interface

- `gem "event_engine-subscribers"` — the Gemfile line that adds the gem; once the
  app boots, the gem registers itself with event_engine as the processor for
  `inline` and `background` events, with no initializer, generator or migration.

## How to use it

1. Check that the host is a Rails app on Rails 7.1.6 or later, below 9, running
   Ruby 3.2 or later. If it is not, stop and tell the developer the gem cannot be
   installed there.
2. Check whether event_engine is already set up: the `Gemfile` lists
   `event_engine` and an initializer calls `EventEngine.configure`. If it is not,
   hand off to the `event_engine-install` local first and return here when it is
   done. This gem requires event_engine 0.2.0 or later.
3. Add the gem to the host's `Gemfile`:

   ```ruby
   gem "event_engine-subscribers"
   ```

4. Run:

   ```
   bundle install
   ```

   This edits `Gemfile.lock`.
5. Check which Active Job backend the host uses, in
   `config.active_job.queue_adapter` in `config/application.rb` or
   `config/environments/*.rb`. Background events are enqueued on the `default`
   queue. Ask the developer:
   - Will this app send any events to `background`?
   - If yes and no backend is configured, which backend should run the jobs? Do
     not pick one.
   - If yes and the backend only processes the queues it is configured to list,
     is `default` among them?
6. Confirm the gem loads in the host:

   ```
   bin/rails runner 'puts EventEngine::Subscribers::VERSION'
   ```

   It prints the installed version. An error here means step 3 or 4 did not take.

## Conventions

- There is nothing else to configure. The gem has no settings, no generator, no
  migration and no tables.
- The gem registers for `inline` and `background` only after the host finishes
  booting. Do not register it with event_engine by hand.
- Re-run `bundle install` after changing the gem's version in the `Gemfile`.
  Nothing else needs re-syncing.
- Background jobs are retried only by whatever the host's job backend does; the
  gem adds no retry of its own.
- Out of scope: writing subscribers, choosing which process type an event runs
  on, and test setup belong to `event_engine-subscribers-develop`. Setting up
  event_engine itself belongs to `event_engine-install`.
