module EventEngine
  module Delivery
    class Processor
      PROCESS_TYPES = %i[durable broker].freeze

      def call(event)
        outbox_event = OutboxWriter.write(event.to_h)

        ActiveSupport::Notifications.instrument("event_engine.event_emitted", {
          event_name: outbox_event.event_name,
          event_version: outbox_event.event_version,
          event_id: outbox_event.id,
          idempotency_key: outbox_event.idempotency_key,
          aggregate_type: outbox_event.aggregate_type,
          aggregate_id: outbox_event.aggregate_id,
          aggregate_version: outbox_event.aggregate_version
        })

        Delivery.enqueue do
          OutboxPublisher.new(
            router: OutboxRouter.new(transport: Delivery.configuration.transport),
            batch_size: Delivery.configuration.batch_size
          ).call
        end

        outbox_event
      end
    end
  end
end
