require "test_helper"

module EventEngine
  module Delivery
    class HandlerRegistrationTest < ActiveSupport::TestCase
      test "the engine dispatches a durable event to this gem's handler" do
        event = ::EventEngine::Event.new(
          event_name: :cow_fed,
          event_version: 1,
          event_type: :domain,
          process_type: :durable,
          payload: { weight: 1200 },
          occurred_at: Time.current
        )

        assert_difference "::EventEngine::OutboxEvent.count", 1 do
          ::EventEngine.dispatch(event)
        end
      end
    end
  end
end
