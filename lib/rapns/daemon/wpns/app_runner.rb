module Rapns
  module Daemon
    module Wpns
      class AppRunner < Rapns::Daemon::AppRunner
        protected

        def new_delivery_handler
          DeliveryHandler.new(app)
        end
      end
    end
  end
end
