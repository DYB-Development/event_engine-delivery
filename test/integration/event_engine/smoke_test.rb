require "test_helper"
require "tempfile"
require "json"

class EventEngineSmokeTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    EventEngine::OutboxEvent.delete_all
  end

  class Cow
    attr_reader :weight

    def initialize(weight:)
      @weight = weight
    end
  end

  class CowFed < EventEngine::EventDefinition
    event_name :cow_fed
    event_type :domain

    input :cow
    required_payload :weight, from: :cow, attr: :weight
  end

  test "end-to-end event emission publishes via outbox" do
    # --- Arrange -------------------------------------------------------------

    transport = EventEngine::Transports::InMemoryTransport.new

    EventEngine::Delivery.configure do |c|
      c.delivery_adapter = :inline
      c.transport = transport
      c.batch_size = 10
      c.max_attempts = 5
    end

    schema_file = Tempfile.new([ "event_schema", ".json" ])
    schema_file.write(JSON.generate([ CowFed.schema.to_h ]))
    schema_file.flush

    # Boot engine from schema file
    EventEngine.boot_from_schema!(
      schema_path: schema_file.path,
      registry: EventEngine::SchemaRegistry.new
    )

    cow = Cow.new(weight: 1200)

    # --- Act -----------------------------------------------------------------

    EventEngine.emit(:cow_fed, inputs: { cow: cow })

    # Inline delivery should have drained immediately
    outbox = EventEngine::OutboxEvent.last

    # --- Assert --------------------------------------------------------------

    assert_not_nil outbox, "Expected an OutboxEvent to be created"
    assert_equal "cow_fed", outbox.event_name
    assert_equal({ "weight" => 1200 }, outbox.payload)

    assert_not_nil outbox.published_at, "Expected event to be marked published"

    assert_equal 1, transport.events.size

    published = transport.events.first
    assert_equal "cow_fed", published.event_name
    assert_equal({ "weight" => 1200 }, published.payload)
  ensure
    schema_file&.unlink
  end
end
