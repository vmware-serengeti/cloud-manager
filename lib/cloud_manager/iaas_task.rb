###############################################################################
#   Copyright (c) 2012-2013 VMware, Inc. All Rights Reserved.
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

# @version 0.5.0

module Serengeti
  module CloudManager
    class IaasTask
      def initialize(options = [])
        @cloud = Serengeti::CloudManager::Cloud.new(self, options)
        @output_lock = Mutex.new
        @finished = nil
      end

      def logger
        Serengeti::CloudManager.logger
      end

      #############################################
      # Get info from caller
      def wait_for_completion()
        @output_lock.synchronize do
          while !finished?
            sleep(1)
          end
          return @cloud.get_result
        end
        nil
      end

      def finished?; !@finished.nil? end

      def get_result; @cloud.get_result end

      def get_progress; @cloud.get_progress end

      def abort
        @cloud.need_abort = true
        logger.warn("Do not implement abort function")
      end

      def release_connection; @cloud.release_connection end

      #############################################
      # Set info from worker thread
      def set_finish(finish)
        @output_lock.synchronize do
          logger.debug("set finish:#{finish}")
          @finished = finish
        end
      end

      def start
        logger.debug("call cloud.start...")
        @cloud.start()
      end

      def stop
        logger.debug("call cloud.stop...")
        @cloud.stop()
      end

      def list_vms(options = {})
        logger.debug("call cloud.list_vms...")
        @cloud.list_vms(options)
      end

      def create
        logger.debug("call cloud.create_and_update ...")
        @cloud.create()
      end

      def delete
        logger.debug("call cloud.delete...")
        @cloud.delete()
      end

      def reconfig
        logger.debug("call cloud.reconfig...")
        @cloud.reconfig()
      end

      def Cluster
        Cluster.new(@cloud)
      end
      def Groups
        Groups.new(@cloud)
      end
    end
  end
end
