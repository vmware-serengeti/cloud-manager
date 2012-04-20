#Resource infomation
module VHelper::CloudManager
  class IaasProcess
    attr_accessor :cluster_name
    attr_accessor :progress
    attr_accessor :result
    attr_accessor :finished
    attr_accessor :status
    def initialize
      @progress = 0
      @finished = false
      @status = "birth"
      @result = ""
    end
    def finished? ;@finished end
    def inspect
      "#{@progress}%, finished ?#{@finished}, #{@status}, servers:\n#{result.inspect}"
    end
  end

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

    def initialize
      @success = false
      @finished = 0
      @failed = 0
      @total = 0
      @deploy = 0
      @waiting = 0
      @waiting_start = 0
      @servers = []
    end

    def succeed? ; @succeed end

    def inspect
      msg = "total:#{total} sucess:#{success} failed:#{failure} running:#{running} [waiting:#{waiting} waiting_start:#{waiting_start} deploy:#{deploy} ]\n"
      servers.each {|vm| msg<<vm.inspect}
      msg
    end
  end

  class IaasTask
    def initialize(cluster_definition, cloud_provider)
      @cluster_definition = cluster_definition
      @cloud_provider = cloud_provider
      @logger = Logger.new
      @vhelper = VHelper::CloudManager::VHelperCloud.new(@logger, @cluster_definition)

      @output_lock = Mutex.new
      @finished = nil

      #at_exit { @client.logout }
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

    def finished?
      return !@finished.nil?
    end

    def get_result
      return @vhelper.get_result
    end

    def get_progress
      return @vhelper.get_progress
    end

    def abort
      @vhelper.need_abort = true
      @logger.debug("Do not implement abort function")
    end

    def release_connection
      @vhelper.release_connection
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

