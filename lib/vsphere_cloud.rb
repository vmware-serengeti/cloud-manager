require "./cloud_item"
require "./cloud_placement"
require "./cloud_deploy"
require "./client"
require "./vhelper_cloud"

#Resource infomation
module VHelper::VSphereCloud
  class Cloud
    def initialize(vhelper_options)
      @cloud_provider = vhelper_options["cloud_provider"]
      @cluster_info = vhelper_options["cluster_definition"]
      @logger = vhelper_options["logger"]
      @vhelper = VHelper::VSphereCloud::VHelperCloud.new(@logger)

      @output_lock = Mutex.new
      @finished = nil

      @result = @progress = "Initializing"

      #at_exit { @fog_client.logout }
    end

    #############################################
    # Get info from caller
    def wait_complete()
      @output_lock.synchronize do
        return @result.dup if @finished
        return nil
      end
    end

    def get_result
      @output_lock.synchronize do
        return @result.dup
      end
    end

    def get_progress
      @output_lock.synchronize do
        return @progress.dup
      end
    end

    #############################################
    # Set info from worker thread
    def set_result(result)
      @output_lock.synchronize do
        @result = result
      end
    end

    def set_progress(progress)
      @output_lock.synchronize do
        @progress = progress
      end
    end

    def set_finish(finish)
      @output_lock.synchronize do
        @finished = finish
      end
    end

    def work
      @logger.debug("call cloud.work...")
      return @vhelper.work(@cloud_provider, @cluster_info, self)
    end

    def self.createService(vhelper_options, options={})
      cloud = Cloud.new(vhelper_options)
      if (options["sync"] == true)
        cloud.work
      else
        # options["sync"] == false
        Thread.new do
          cloud.work
        end
      end
      cloud
    end

  end
end

