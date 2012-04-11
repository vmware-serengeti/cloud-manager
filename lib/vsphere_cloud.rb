require "./cloud_item"
require "./cloud_placement"
require "./cloud_deploy"
require "./client"
require "./vhelper_cloud"

#Resource infomation
module VHelper::CloudManager
  class IaasProcess 
    attr_accessor :progress
    attr_accessor :results
    def initialize
      @progress = 0
      @results = nil
    end
  end

  class IaasServer
    attr_accessor :error_code
    attr_accessor :error_msg
    attr_accessor :vm_name
    attr_accessor :cluster_name
    attr_accessor :group_name
    attr_accessor :created
    attr_accessor :powered_on
    attr_accessor :ip_address

    def initialize
      @error_code = 0
      @error_msg = "No Error"
      @vm_name = ""
      @cluster_name = ""
      @group_name = ""
      @created = false
      @powered_on = false
      @ip_address = ""
    end
  end

  class IaasResult
    attr_accessor :success
    attr_accessor :finished
    attr_accessor :running
    attr_accessor :failed
    attr_accessor :total
    attr_accessor :servers

    def initialize
      @success = false
      @finished = 0
      @failed = 0
      @total = 0
      @servers = []
    end
  end

  class IaasTask
    def initialize(cluster_definition, cloud_provider)
      @cluster_definition = cluster_definition
      @cloud_provider = cloud_provider
      @logger = Logger.new
      @vhelper = VHelper::CloudManager::VHelperCloud.new(@logger)

      @output_lock = Mutex.new
      @finished = nil

      #at_exit { @client.logout }
    end

    #############################################
    # Get info from caller
    def wait_for_completion()
      @output_lock.synchronize do
        unless @finished.nil?
          @logger.debug("finished")
          result = @vhelper.get_result 
          return result[1]
        end
        @logger.debug("Do not finished! #{@finished}")
        return nil
      end
    end

    def get_result
      return @vhelper.get_result[1]
    end

    def get_progress
      progress = IaasProcess.new
      result, percent = @vhelper.get_result
      progress.progress = percent
      progress.results = result
      return progress
    end

    def abort
      @vhelper.need_abort = true
      @logger.debug("Do not implement abort function")
    end

    #############################################
    # Set info from worker thread
    def set_finish(finish)
      @output_lock.synchronize do
        @logger.debug("set finish:#{finish}")
        @finished = finish
      end
    end

    def create_and_update
      @logger.debug("call cloud.create_and_update ...")
      return @vhelper.create_and_update(@cloud_provider, @cluster_definition, self)
    end

    def delete
      @logger.debug("call cloud.delete...")
      return @vhelper.delete(@cloud_provider, @cluster_definition, self)
    end

    def self.delete_cluster(cluster_definition, cloud_provider, options={})
      cloud = IaasTask.new(cluster_definition, cloud_provider)
      if (options["wait"])
        cloud.delete
      else
        # options["sync"] == false
        Thread.new do
          cloud.delete
        end
      end
      cloud
    end

    def self.create_cluster(cluster_definition, cloud_provider, options={})
      cloud = IaasTask.new(cluster_definition, cloud_provider)
      if (options["wait"])
        cloud.create_and_update
      else
        # options["sync"] == false
        Thread.new do
          cloud.create_and_update
        end
      end
      cloud
    end

  end
end

