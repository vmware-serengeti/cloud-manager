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
    class IaasTask
      def initialize(cluster_definition, cloud_provider, cluster_data, targets)
        @cluster_definition = cluster_definition
        @cloud_provider = cloud_provider
        @cluster_data = cluster_data
        @targets = targets
        @serengeti = Serengeti::CloudManager::Cloud.new(@cluster_definition, @targets)

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
          return @serengeti.get_result
        end
        nil
      end

      def finished?; !@finished.nil? end

      def get_result; @serengeti.get_result end

      def get_progress; @serengeti.get_progress end

      def abort
        @serengeti.need_abort = true
        logger.warn("Do not implement abort function")
      end

      def release_connection; @serengeti.release_connection end

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
        @serengeti.start(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def stop
        logger.debug("call cloud.stop...")
        @serengeti.stop(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def list_vms
        logger.debug("call cloud.list_vms...")
        @serengeti.list_vms(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def create_and_update
        logger.debug("call cloud.create_and_update ...")
        @serengeti.create_and_update(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def delete
        logger.debug("call cloud.delete...")
        @serengeti.delete(@cloud_provider, @cluster_definition, @cluster_data, self)
      end
    end
  end
end
