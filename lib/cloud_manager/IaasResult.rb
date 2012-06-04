module Serengeti
  module CloudManager
    class IaasResult
      attr_accessor :succeed
      attr_accessor :success
      attr_accessor :running
      attr_accessor :deploy
      attr_accessor :failure
      attr_accessor :waiting
      attr_accessor :waiting_start
      attr_accessor :total
      attr_accessor :servers
      attr_accessor :error_msg

      def initialize
        @success = false
        @finished = 0
        @failed = 0
        @total = 0
        @deploy = 0
        @waiting = 0
        @error_msg = ""
        @waiting_start = 0
        @servers = []
      end

      def succeed? ; @succeed end

      def inspect
        msg = "succeed? #{succeed?} total:#{total} success:#{success} "\
              "failed:#{failure} running:#{running} [waiting:#{waiting} "\
              "waiting_start:#{waiting_start} deploy:#{deploy} ]\n"
        servers.each { |vm| msg<<vm.inspect }
        msg
      end
    end
  end
end
