require './cloud_item'
require './resources'
require './client'
require './vm_group'
require './cluster_diff'
require './cloud_placement'

module VHelper::CloudManager
  class VHelperCloud
    attr_reader :vc_share_datastore_patten
    attr_reader :vc_local_datastore_patten
    attr_reader :vc_req_resource_pools
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
      resource_pool = cloud_provider["vc_resource_pools"]
      #@vc_req_resource_pools = resource_pool.split(',').delete_if(&:empty?)
      @vc_req_resource_pools = [resource_pool]
      @vc_req_datacenter = cloud_provider["vc_datacenter"]
      vc_req_cluster_string = cloud_provider["vc_clusters"]
      #@vc_req_clusters = vc_req_cluster_string.split(',').delete_if(&:empty?)
      @vc_req_clusters = [vc_req_cluster_string]
      @vc_address = cloud_provider["vc_address"]
      @vc_username = cloud_provider["vc_username"]
      @vc_password = cloud_provider["vc_password"]
      @vc_share_datastore_patten = cloud_provider["vc_share_datastore_patten"]
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

    def delete(cloud_provider, clusters_info, task)
      @logger.debug("enter delete ... not implement")
      #TODO add code here to delete all cluster
    end

    def create_and_update(cloud_provider, clusters_info, task)
      @logger.debug("enter create_and_update...")
      create_cloud_provider(cloud_provider)
      @vm_lock.synchronize do 
        @deploy_vms = {} 
        @existed_vms = {}
        @failure_vms = {}
      end
      #FIXME we only support one cluster, currently

      @logger.debug("#{clusters_info.inspect}")
      cluster_info = clusters_info[0]
      @logger.debug("Begin vHelper work...")

      begin
        ###########################################################
        # Connect to Cloud server
        @logger.debug("Connect to Cloud Server...")
        @status = CLUSTER_CONNECT
        @client = ClientFactory.create(@client_name, @logger)
        @client.login(@vc_address, @vc_username, @vc_password)

        @logger.debug("Create Resources ...")
        @resources = Resources.new(@client, self)

        ###########################################################
        # Create inputed vm_group from vhelper input
        @logger.debug("Create vm group from vhelper input...")
        vm_groups_input = create_vm_group_from_vhelper_input(cluster_info)
        vm_groups_existed = {}
        cluster_changes = []
        dc_resources = {}
        @status = CLUSTER_FETCH_INFO
        dc_resources = @resources.fetch_datacenter

        ###########################################################
        # Create existed vm groups
        @logger.debug("Create vm group from resources...")
        vm_groups_existed = create_vm_group_from_resources(dc_resources)
        @logger.info("Finish collect vm_group info from resources")

        unless vm_groups_existed.empty?
          ###########################################################
          #Checking and do difference
          @status = CLUSTER_UPDATE
          nodifference, cluster_changes = cluster_diff(dc_resources, vm_groups_input, vm_groups_existed)
          if nodifference
            @status = CLUSTER_DONE
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

          @status = CLUSTER_DEPLOY
          successful = cluster_deploy(cluster_changes , placement)
          break if successful

          @status = CLUSTER_FETCH_INFO
          dc_resources = @resources.fetch_datacenter
          #TODO add all kinds of error handlers here
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

    def get_result_by_vms(vms)
      vms.each_value do |vm|
        vm_status = IaasServer.new
        vm_status.vm_name = vm.name
        result = get_from_vm_name(vm.name)
        vm_status.cluster_name = result[1]
        vm_status.group_name = result[2]
        yield(vm, vm_status)
      end
    end

    def get_result
      result = IaasResult.new
      @vm_lock.synchronize do 
        result.running = @deploy_vms.size
        result.finished = @existed_vms.size 
        result.failed = @failure_vms.size
        get_result_by_vms(@deploy_vms) do
        end
        get_result_by_vms(@existed_vms) do
          vm_status.create = true
          vm_status.powered_on = vm.powerd_on
          vm_status.ip_address = vm.ip_address
        end
        get_result_by_vms(@failure_vms) do
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
