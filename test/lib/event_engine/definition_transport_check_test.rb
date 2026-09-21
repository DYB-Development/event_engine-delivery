require "test_helper"

module EventEngine
  class DefinitionTransportCheckTest < ActiveSupport::TestCase
    def registry_for_sale_processed
      schema = EventDefinition::Schema.new(
        event_name: :sale_processed,
        event_version: 1,
        event_type: :domain,
        required_inputs: [],
        optional_inputs: [],
        payload_fields: []
      )
      event_schema = EventSchema.new
      event_schema.register(schema)
      event_schema.finalize!

      registry = SchemaRegistry.new
      registry.reset!
      registry.load_from_schema!(event_schema)
      registry
    end

    def rules_making_it(process_type)
      ProcessingRules.new(events: { sale_processed: process_type })
    end

    def capture_log(registry:, transport:, processing_rules:)
      io = StringIO.new
      DefinitionTransportCheck.run(
        registry: registry,
        transport: transport,
        logger: Logger.new(io),
        processing_rules: processing_rules
      )
      io.string
    end

    test "warns when a :broker event has no real transport configured" do
      output = capture_log(
        registry: registry_for_sale_processed,
        transport: Transports::NullTransport.new,
        processing_rules: rules_making_it(:broker)
      )

      assert_match(/sale_processed/, output)
    end

    test "stays silent when a real transport is configured" do
      output = capture_log(
        registry: registry_for_sale_processed,
        transport: Transports::InMemoryTransport.new,
        processing_rules: rules_making_it(:broker)
      )

      assert_equal "", output
    end
  end
end
