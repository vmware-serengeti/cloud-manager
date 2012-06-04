module Serengeti
  module CloudManager
    class IaasTask
      def initialize(cluster_definition, cloud_provider, cluster_data)
        @cluster_definition = cluster_definition
        @cloud_provider = cloud_provider
        @cluster_data = cluster_data
        @logger = Serengeti::CloudManager::Cloud.Logger
        @serengeti = Serengeti::CloudManager::Cloud.new(@cluster_definition)

        @output_lock = Mutex.new
        @finished = nil
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
        @logger.warn("Do not implement abort function")
      end

      def release_connection; @serengeti.release_connection end

      #############################################
      # Set info from worker thread
      def set_finish(finish)
        @output_lock.synchronize do
          @logger.debug("set finish:#{finish}")
          @finished = finish
        end
      end

      def start
        @logger.debug("call cloud.start...")
        return @serengeti.start(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def stop
        @logger.debug("call cloud.stop...")
        return @serengeti.stop(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def list_vms
        @logger.debug("call cloud.list_vms...")
        return @serengeti.list_vms(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def create_and_update
        @logger.debug("call cloud.create_and_update ...")
        return @serengeti.create_and_update(@cloud_provider, @cluster_definition, @cluster_data, self)
      end

      def delete
        @logger.debug("call cloud.delete...")
        return @serengeti.delete(@cloud_provider, @cluster_definition, @cluster_data, self)
      end
    end
  end
end
