module EventEngine
  module Delivery
    class Engine < ::Rails::Engine
      engine_name "event_engine_delivery"

      initializer "event_engine.delivery.register_handler" do
        config.after_initialize do
          EventEngine.register_handler(Handler.new, process_types: :all)
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
