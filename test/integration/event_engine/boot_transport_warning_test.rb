require "test_helper"
require "tempfile"
require "json"

class BootTransportWarningTest < ActiveSupport::TestCase
  class SaleProcessed < EventEngine::EventDefinition
    event_name :sale_processed
    event_type :domain

    input :sale
    required_payload :total, from: :sale, attr: :total
  end

  test "boot warns when a :broker event has no real transport" do
    schema_file = Tempfile.new([ "event_schema", ".json" ])
    schema_file.write(JSON.generate([ SaleProcessed.schema.to_h.merge(event_version: 1) ]))
    schema_file.flush

    original = EventEngine::Delivery.configuration.instance_variable_get(:@logger)
    original_transport = EventEngine::Delivery.configuration.transport
    original_adapter = EventEngine::Delivery.configuration.delivery_adapter
    io = StringIO.new
    EventEngine::Delivery.configuration.instance_variable_set(:@logger, Logger.new(io))
    EventEngine::Delivery.configuration.transport = EventEngine::Transports::NullTransport.new
    EventEngine::Delivery.configuration.delivery_adapter = :inline

    registry = EventEngine::SchemaRegistry.new
    EventEngine.boot_from_schema!(
      schema_path: schema_file.path,
      registry: registry
    )
    EventEngine::DefinitionTransportCheck.run(
      registry: registry,
      transport: EventEngine::Delivery.configuration.transport,
      logger: EventEngine::Delivery.configuration.logger,
      processing_rules: EventEngine::ProcessingRules.new(events: { sale_processed: :broker })
    )

    assert_match(/sale_processed/, io.string)
  ensure
    EventEngine::Delivery.configuration.instance_variable_set(:@logger, original)
    EventEngine::Delivery.configuration.transport = original_transport
    EventEngine::Delivery.configuration.delivery_adapter = original_adapter
  end
end
