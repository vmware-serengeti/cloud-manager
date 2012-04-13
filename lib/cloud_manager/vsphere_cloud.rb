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
        sleep(1)
        unless @finished.nil?
          result = @vhelper.get_result 
          return result[1]
        end
      end
      nil
    end

    def finish?
      return !@finished.nil?
    end

    def get_result
      return @vhelper.get_result[1]
    end

    def get_progress
      progress = IaasProcess.new
      percent, result = @vhelper.get_result
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

