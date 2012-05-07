module VHelper::CloudManager
  class VHelperCloud
    attr_accessor :name
    attr_accessor :vc_req_resource_pools
    attr_accessor :vc_address
    attr_accessor :vc_username
    attr_accessor :vc_password

    attr_accessor :status
    attr_accessor :clusters
    attr_accessor :vm_groups
    attr_accessor :vms
    attr_reader :input_cluster_info
    attr_reader :action

    attr_accessor :placement_failed
    attr_accessor :cloud_error_msg_que

    attr_reader :vc_share_datastore_pattern
    attr_reader :vc_local_datastore_pattern
    attr_reader :vc_req_datacenter
    attr_reader :vc_req_clusters
    attr_reader :vc_req_rps

    attr_reader :allow_mixed_datastores
    attr_reader :racks
    attr_reader :need_abort

    def initialize(logger, cluster_info)
      @logger = logger
      @dc_resource = nil
      @clusters = nil
      @vm_lock = Mutex.new
      @deploy_vms = {}
      @existed_vms = {}
      @finished_vms = {}
      @failure_vms = {}
      @preparing_vms = {}
      @need_abort = nil
      @cluster_name = cluster_info["name"]

      @status = CLUSTER_BIRTH
      @rs_lock = Mutex.new
      @client = nil
      @success = false
      @finished = false
      @placement_failed = 0
      @cloud_error_msg_que = []
    end

    def add_existed_vm(vm)
      @logger.debug("Add existed vm")
      @vm_lock.synchronize {
        @existed_vms[vm.name] = vm
      }
    end

    def mov_vm(vm, src_vms, des_vms)
      @vm_lock.synchronize {
        return if !src_vms.has_key?(vm.name)
        src_vms.delete(vm.name)
        des_vms[vm.name] = vm
      }
    end

    def req_clusters_rp_to_hash(a)
      rps = {}
      # FIXME resource_pool's name can be the same between different clusters
      a.each {|v| v["vc_rps"].each { |rp| rps[rp] = v["name"] } }
      rps
    end

    def create_cloud_provider(cloud_provider)
      @name = cloud_provider["name"]
      @vc_req_datacenter = cloud_provider["vc_datacenter"]
      @vc_req_clusters = cloud_provider["vc_clusters"]
      @vc_req_rps = req_clusters_rp_to_hash(@vc_req_clusters)
      @logger.debug("Show clusters_req:#{@vc_req_rps}")

      @vc_address = cloud_provider["vc_addr"]
      @vc_username = cloud_provider["vc_user"]
      @vc_password = cloud_provider["vc_pwd"]
      @vc_share_datastore_pattern = cloud_provider["vc_shared_datastore_pattern"]
      @vc_local_datastore_pattern = cloud_provider["vc_local_datastore_pattern"]
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

    def prepare_working(cluster_info)
      ###########################################################
      # Connect to Cloud server
      #@cluster_name = cluster_info["name"]
      @logger.debug("Connect to Cloud Server #{@client_name} #{@vc_address} user:#{@vc_username}/#{vc_password}...")
      @input_cluster_info = cluster_info
      @status = CLUSTER_CONNECT
      @client = ClientFactory.create(@client_name, @logger)
      @client.login(@vc_address, @vc_username, @vc_password)

      @logger.debug("Create Resources ...")
      @resources = Resources.new(@client, self)

      ###########################################################
      # Create inputed vm_group from vhelper input
      @logger.debug("Create vm group from vhelper input...")
      vm_groups_input = create_vm_group_from_vhelper_input(cluster_info, @vc_req_datacenter)

      log_obj_to_file(vm_groups_input, 'vm_groups_input')
      vm_groups_existed = {}
      dc_resources = {}
      @status = CLUSTER_FETCH_INFO
      dc_resources = @resources.fetch_datacenter(@vc_req_datacenter)

      log_obj_to_file(dc_resources, 'dc_resource-first')
      @logger.debug("Create vm group from resources...")
      vm_groups_existed = create_vm_group_from_resources(dc_resources, cluster_info["name"])
      log_obj_to_file(vm_groups_existed, 'vm_groups_existed')

      @logger.info("Finish collect vm_group info from resources")
      [dc_resources, vm_groups_existed, vm_groups_input]
    end

    def release_connection
      return if @client.nil?
      @client.logout
      @client = nil
    end

    def log_obj_to_file(obj, str)
      File.open("#{str}.yaml", 'w'){|f| YAML.dump(obj, f)} 
    end

    def action_process act
      begin
        @logger.debug("begin action:#{act}")
        @action = act
        yield 
        @logger.debug("finished action:#{act}")
      ensure
        @action = CLOUD_WORK_NONE
      end
    end
=begin
    def start(cloud_provider, cluster_info, task)
      action_process (CLOUD_WORK_START) {
        @logger.debug("enter cluster start...")
        create_cloud_provider(cloud_provider)
        dc_resources, vm_groups_existed, vm_groups_input = prepare_working(cluster_info)
       }
    end

    def stop(cloud_provider, cluster_info, task)
      action_process (CLOUD_WORK_STOP) {
        @logger.debug("enter cluster stop...")
        create_cloud_provider(cloud_provider)
        dc_resources, vm_groups_existed, vm_groups_input = prepare_working(cluster_info)
       }
    end
=end

    def list_vms(cloud_provider, cluster_info, task)
      action_process (CLOUD_WORK_LIST) {
        @logger.debug("enter list_vms...")
        create_cloud_provider(cloud_provider)
        dc_resources, vm_groups_existed, vm_groups_input = prepare_working(cluster_info)
        get_result.servers
      }
    end

    def cluster_failed(task)
      @logger.debug("Enter Cluster_failed")
      task.set_finish("failed")
      @success = false
      @finished = true
    end

    def cluster_done(task)
      @logger.debug("Enter cluster_done")
      # TODO finish cluster information
      task.set_finish("success")
      @success = true
      @finished = true
    end

  end
end
