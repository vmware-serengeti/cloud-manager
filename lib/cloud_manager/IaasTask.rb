module VHelper
  module CloudManager
    class IaasTask
      def initialize(cluster_definition, cloud_provider)
        @cluster_definition = cluster_definition
        @cloud_provider = cloud_provider
        @logger = VHelper::CloudManager::VHelperCloud.Logger
        @vhelper = VHelper::CloudManager::VHelperCloud.new(@logger, @cluster_definition)

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
          return @vhelper.get_result 
        end
        nil
      end

      def finished?; !@finished.nil? end

      def get_result; @vhelper.get_result end

      def get_progress; @vhelper.get_progress end

      def abort
        @vhelper.need_abort = true
        @logger.debug("Do not implement abort function")
      end

      def release_connection; @vhelper.release_connection end

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
        return @vhelper.start(@cloud_provider, @cluster_definition, self)
      end

      def stop
        @logger.debug("call cloud.stop...")
        return @vhelper.stop(@cloud_provider, @cluster_definition, self)
      end

      def list_vms
        @logger.debug("call cloud.list_vms...")
        return @vhelper.list_vms(@cloud_provider, @cluster_definition, self)
      end

      def create_and_update
        @logger.debug("call cloud.create_and_update ...")
        return @vhelper.create_and_update(@cloud_provider, @cluster_definition, self)
      end

      def delete
        @logger.debug("call cloud.delete...")
        return @vhelper.delete(@cloud_provider, @cluster_definition, self)
      end
    end
  end
end
