require "test_helper"

module EventEngine
  module Delivery
    class ProcessorRegistrationTest < ActiveSupport::TestCase
      teardown { ::EventEngine.processing_rules = nil }

      def event(process_type)
        ::EventEngine::Event.new(
          event_name: :cow_fed,
          event_version: 1,
          event_type: :domain,
          process_type: process_type,
          payload: { weight: 1200 },
          occurred_at: Time.current
        )
      end

      test "the engine processes a durable event with this gem's processor, writing it to the outbox once" do
        ::EventEngine.processing_rules = ::EventEngine::ProcessingRules.new(events: { cow_fed: :durable })

        assert_difference "::EventEngine::OutboxEvent.count", 1 do
          ::EventEngine.process(event(:durable))
        end
      end
    end
  end
end
