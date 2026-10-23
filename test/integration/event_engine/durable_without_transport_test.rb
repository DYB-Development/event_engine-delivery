require "test_helper"

class DurableWithoutTransportTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    EventEngine::Delivery.configure do |config|
      config.delivery_adapter = :inline
      config.transport = nil
    end
    EventEngine.processing_rules = EventEngine::ProcessingRules.new(events: { cow_fed: :durable })
  end

  teardown do
    EventEngine::OutboxEvent.delete_all
    EventEngine.processing_rules = nil
    EventEngine::Subscribers::Registry.clear!
  end

  test "a durable event reaches its subscribers when no transport is configured" do
    received = []
    Class.new(EventEngine::Subscribers::Base) do
      subscribes_to :cow_fed
      define_method(:handle) { |event| received << event.payload }
    end

    EventEngine.process(EventEngine::Event.new(event_name: :cow_fed, event_version: 1, event_type: :domain, process_type: :durable, payload: { weight: 1200 }, occurred_at: Time.current))

    assert_equal [ { weight: 1200 } ], received
  end
end
