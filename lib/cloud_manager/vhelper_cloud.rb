module VHelper::CloudManager
  class VHelperCloud
    attr_reader :vc_share_datastore_patten
    attr_reader :vc_local_datastore_patten
    attr_reader :vc_req_datacenter
    attr_reader :vc_req_clusters
    attr_reader :allow_mixed_datastores
    attr_reader :racks
    attr_reader :need_abort

    def initialize(logger)
      @logger = logger
      @dc_resource = nil
      @clusters = nil
      @vm_lock = Mutex.new
      @deploy_vms = {}
      @existed_vms = {}
      @failure_vms = {}
      @need_abort = nil

      @status = CLUSTER_BIRTH
      @rs_lock = Mutex.new
      @client = nil
    end

    def add_deploying_vm(vm)
      @vm_lock.synchronize do
        @deploy_vms[vm.name] = vm
      end
    end

    def deploying_vm_move_to_existed(vm)
      @vm_lock.synchronize do
        @deploy_vms.delete(vm)
        @existed_vms[vm.name] = vm
      end
    end

    def create_cloud_provider(cloud_provider)
      @name = cloud_provider["name"]
      #@vc_req_resource_pools = resource_pool.split(',').delete_if(&:empty?)
      @vc_req_datacenter = cloud_provider["vc_datacenter"]
      @vc_req_clusters = cloud_provider["vc_clusters"]
      @vc_address = cloud_provider["vc_addr"]
      @vc_username = cloud_provider["vc_user"]
      @vc_password = cloud_provider["vc_pwd"]
      @vc_share_datastore_patten = cloud_provider["vc_shared_datastore_patten"]
      @vc_local_datastore_patten = cloud_provider["vc_local_datastore_patten"]
      @client_name = cloud_provider["cloud_adapter"] || "fog"
      @allow_mixed_datastores = nil
      @racks = nil
    end

    def attach_adapter(client)
      @client = client
    end

    def inspect
      "<vHelperCloud: #{@name} vc: #{@vc_address} status: #{@status} client: #{@client.inspect}>"
    end

    def delete(cloud_provider, cluster_info, task)
      @logger.debug("enter delete ... not implement")
      #TODO add code here to delete all cluster
    end

    def create_and_update(cloud_provider, cluster_info, task)
      @logger.debug("enter create_and_update...")
      create_cloud_provider(cloud_provider)
      @vm_lock.synchronize do
        @deploy_vms = {}
        @existed_vms = {}
        @failure_vms = {}
      end
      #FIXME we only support one cluster, currently

      @logger.debug("#{cluster_info.inspect}")
      @logger.debug("Begin vHelper work...")

      begin
        ###########################################################
        # Connect to Cloud server
        @logger.debug("Connect to Cloud Server #{@vc_address} user:#{@vc_username}/#{vc_password}...")
        @status = CLUSTER_CONNECT
        @client = ClientFactory.create(@client_name, @logger)
        @client.login(@vc_address, @vc_username, @vc_password)

        @logger.debug("Create Resources ...")
        @resources = Resources.new(@client, self)

        ###########################################################
        # Create inputed vm_group from vhelper input
        @logger.debug("Create vm group from vhelper input...")
        vm_groups_input = create_vm_group_from_vhelper_input(cluster_info)
        File.open("vm_groups_input.yaml", 'w'){|f| YAML.dump(vm_groups_input, f)} 
        vm_groups_existed = {}
        cluster_changes = []
        dc_resources = {}
        @status = CLUSTER_FETCH_INFO
        dc_resources = @resources.fetch_datacenter

        File.open("dc_resource-first.yaml", 'w'){|f| YAML.dump(dc_resources, f)} 
        ###########################################################
        # Create existed vm groups
        
        # TODO later
        #@logger.debug("Create vm group from resources...")
        #vm_groups_existed = create_vm_group_from_resources(dc_resources)
        #File.open("vm_groups_existed.yaml", 'w'){|f| YAML.dump(vm_groups_existed, f)} 
        #@logger.info("Finish collect vm_group info from resources")

        unless vm_groups_existed.empty?
          ###########################################################
          #Checking and do difference
          @status = CLUSTER_UPDATE
          nodifference, cluster_changes = cluster_diff(dc_resources, vm_groups_input, vm_groups_existed)
          if nodifference
            @status = CLUSTER_DONE
          else
            File.open("cluster_changes.yaml", 'w'){|f| YAML.dump(cluster_changes, f)} 
          end
        end
      rescue => e
        @logger.debug("Prepare working failed.")
        @logger.debug("#{e} - #{e.backtrace.join("\n")}")
        cluster_failed(task)
        #TODO add all kinds of error handlers here
        raise e
      end
      if @status == CLUSTER_DONE
        cluster_done(task)
        return
      end

      retry_num = 3

      retry_num.times do |cycle_num|
        begin
          ###########################################################
          #Caculate cluster placement
          @status = CLUSTER_PLACE
          placement = cluster_placement(dc_resources, vm_groups_input, vm_groups_existed)
          File.open("placement.yaml", 'w'){|f| YAML.dump(placement, f)} 

          @status = CLUSTER_DEPLOY
          successful = cluster_deploy(cluster_changes , placement)
          break if successful

          @status = CLUSTER_FETCH_INFO
          dc_resources = @resources.fetch_datacenter
          #TODO add all kinds of error handlers here
          @logger.info("reload datacenter resources from cloud")
          File.open("dc_resource-#{cycle_num}.yaml", 'w'){|f| YAML.dump(dc_resources, f)} 
        rescue => e
          if cycle_num + 1  >= retry_num
            cluster_failed(task)
            raise
          end
          @logger.debug("Loop placement faild and retry #{cycle_num} loop")
          @logger.debug("#{e} - #{e.backtrace.join("\n")}")
        end
      end
      ###########################################################
      # Cluster deploy successfully
      @status = CLUSTER_DONE
      cluster_done(task)
    end

    def get_result_by_vms(servers, vms)
      vms.each_value do |vm|
        result = get_from_vm_name(vm.name)
        return if result.nil?
        vm.cluster_name = result[1]
        vm.group_name = result[2]
        yield(vm, vm_status)
        servers << vm
      end
    end

    def get_result
      result = IaasResult.new
      @vm_lock.synchronize do
        result.running = @deploy_vms.size
        result.finished = @existed_vms.size
        result.failed = @failure_vms.size
        result.total = result.running + result.finished + result.failed
        get_result_by_vms(result.servers, @deploy_vms) do |vm|
          vm.create = false
        end
        get_result_by_vms(result.servers, @existed_vms) do |vm|
          vm.create = true
        end
        get_result_by_vms(result.servers, @failure_vms) do |vm|
          vm.create = false
          vm_status.error_code = -1
          vm_status.error_msg = vm.error_msg
        end
      end
      [0, result]
    end

    def cluster_failed(task)
      @logger.debug("Enter Cluster_failed")
      task.set_finish("failed")
    end

    def cluster_done(task)
      @logger.debug("Enter cluster_done")
      # TODO finish cluster information
      task.set_finish("success")
    end

  end
end
