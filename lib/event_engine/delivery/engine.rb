module EventEngine
  module Delivery
    class Engine < ::Rails::Engine
      engine_name "event_engine_delivery"

      initializer "event_engine.delivery.register_processor" do
        config.after_initialize do
          processor = Processor.new
          Processor::PROCESS_TYPES.each { |process_type| EventEngine.register_processor(process_type, processor) }
          Engine.send(:start_cloud_reporter!)
        end
      end

      class << self
        private

        def start_cloud_reporter!
          return unless Delivery.configuration.cloud_enabled?

          ::EventEngine::Cloud::Subscribers.subscribe!(reporter: ::EventEngine::Cloud::Reporter.instance)
          ::EventEngine::Cloud::Reporter.instance.start
        end
      end
    end
  end
end
