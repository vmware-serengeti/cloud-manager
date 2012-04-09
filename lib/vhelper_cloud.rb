require './cloud_item'
require './resources'
require './client'
require './vm_group'
require './cluster_diff'
require './cloud_placement'

module VHelper::VSphereCloud
  class VHelperCloud
    attr_reader :vc_share_datastore_patten
    attr_reader :vc_local_datastore_patten
    attr_reader :vc_req_resource_pools
    attr_reader :vc_req_datacenter
    attr_reader :vc_req_clusters
    attr_reader :allow_mixed_datastores
    attr_reader :racks

    def initialize(logger)
      @logger = logger
      @dc_resource = nil
      @clusters = nil
      @vms = nil
      @vm_success = 0
      @vm_fail = 0
      @vm_running = 0

      @lock = Mutex.new
      @status = CLUSTER_BIRTH
      @rs_lock = Mutex.new
      @client = nil
    end

    def create_vhelper_info(vhelper_info)
      @name = vhelper_info["name"]
      resource_pool = vhelper_info["vc_resource_pools"]
      #@vc_req_resource_pools = resource_pool.split(',').delete_if(&:empty?)
      @vc_req_resource_pools = [resource_pool]
      @vc_req_datacenter = vhelper_info["vc_datacenter"]
      vc_req_cluster_string = vhelper_info["vc_clusters"]
      #@vc_req_clusters = vc_req_cluster_string.split(',').delete_if(&:empty?)
      @vc_req_clusters = [vc_req_cluster_string]
      @vc_address = vhelper_info["vc_address"]
      @vc_username = vhelper_info["vc_username"]
      @vc_password = vhelper_info["vc_password"]
      @vc_share_datastore_patten = vhelper_info["vc_share_datastore_patten"]
      @vc_local_datastore_patten = vhelper_info["vc_local_datastore_patten"]
      @client_name = vhelper_info["cloud_adapter"] || "fog"
      @allow_mixed_datastores = nil
      @racks = nil
    end

    def attach_adapter(client)
      @client = client
    end

    def inspect
      "<vHelperCloud: #{@name} vc: #{@vc_address} status: #{@status} client: #{@client.inspect}>"
    end

    def work(vhelper_info, clusters_info, task)
      @logger.debug("enter work...")
      create_vhelper_info(vhelper_info)
      @vm_success = 0
      @vm_fail = 0
      @vm_running = 0
      #FIXME we only support one cluster, currently
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
        cluster_failed(task)
        @logger.debug("#{e} - #{e.backtrace.join("\n")}")
        #TODO add all kinds of error handlers here
        raise e
      end
      if @status == CLUSTER_DONE
        cluster_done(task)
        return
      end

      retry_num = 3

      retry_num.times do |cycleNum|
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
          if cycleNum + 1  >= retryNum
            cluster_failed(task)
            raise
          end
          @logger.debug("Loop placement faild and retry #{cycleNum} loop")
          @logger.debug("#{e} - #{e.backtrace.join("\n")}")
        end
      end
      ###########################################################
      # Cluster deploy successfully
      @status = CLUSTER_DONE
      cluster_done(task)
    end

    def cluster_failed(task)
      @logger.debug("Enter Cluster_failed")
      task.set_result(inspect)
      task.set_finish("failed")
    end

    def cluster_done(task)
      @logger.debug("Enter Cluster_done")
      # TODO finish cluster information
      task.set_result(inspect)
      task.set_finish("success")
    end

  end
end
