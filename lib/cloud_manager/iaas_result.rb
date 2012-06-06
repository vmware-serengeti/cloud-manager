###############################################################################
#    Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
################################################################################

# @since serengeti 0.5.0
# @version 0.5.0

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
              "waiting_start:#{waiting_start} deploy:#{deploy} ]\nerror_msg:#{error_msg}"
        servers.each { |vm| msg<<vm.inspect }
        msg
      end
    end
  end
end
