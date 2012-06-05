module Serengeti
  module CloudManager
    class FogAdapter
      DISK_SIZE_TIMES = 1
      CONNECTION_NUMBER = 5
      include Serengeti::CloudManager::Parallel
      def initialize()
        @logger = Serengeti::CloudManager::Cloud.Logger
        @connection = nil
        @con_lock = Mutex.new
      end

      def login(vc_addr, vc_user, vc_pass)
        return unless @connection.nil?
        connect_list = Array.new(CONNECTION_NUMBER)
        cloud_server = 'vsphere'
        info = {:provider => cloud_server,
          :vsphere_server => vc_addr,
          :vsphere_username => vc_user,
          :vsphere_password => vc_pass,
        }
        @connection = {}
        @connection[:con] = []
        @connection[:err] = []
        group_each_by_threads(connect_list, :callee => 'connect to cloud service') do |con|
          begin
            connection = Fog::Compute.new(info)
            @con_lock.synchronize { @connection[:con] << connection }
          rescue => e
            @con_lock.synchronize { @connection[:err] << e }
          end
        end
        if @connection[:err].size > 0
          @logger.error("#{@connection[:err].size} connections fail to login.\n error is:\n#{@connection[:err].join("\n")}")
          raise "#{@connection[:err].size} connections fail to login."
        end
        @logger.debug("Use #{@connection[:con].size} channels to connect cloud service\n}")
      end

      def fog_op
        con = nil
        while con.nil?
          @con_lock.synchronize { con = @connection[:con].first;@connection[:con].rotate! }
        end
        return yield con
      end

      def logout
        @con_lock.synchronize do
          unless @connection.nil?
            @connection.each { |con| }#con.close }
            #TODO destroy @connection
          end
        end
        @connection = nil
        @logger.info("Disconnect from cloud provider ")
      end

      def clone_vm(vm, options={})
        check_connection
        info = {
          'vm_moid' => vm.template_id,
          'name' => vm.name,
          'wait' => 1,
          'linked_clone' => false, # vsphere 5.0 has a bug with linked clone over 8 hosts, be conservative
          'datastore_moid' => vm.sys_datastore_moid,
          'rp_moid' => vm.resource_pool_moid,
          'host_moid' => vm.host_mob,
          'power_on' => false,
          'cpu' => vm.req_rp.cpu,
          'memory' => vm.req_rp.mem,
        }
        result = fog_op { |con| con.vm_clone(info) }
        @logger.debug("after clone: result :#{result} ")
        update_vm_with_properties_string(vm, result["vm_attributes"])
      end

      def check_connection
        raise "Do not login cloud server, please login first" if @connection.nil?
      end

      def vm_destroy(vm)
        check_connection
        task_state = fog_op { |con| con.vm_destroy('instance_uuid' => vm.instance_uuid) }
      end

      # TODO add option to force hard/soft reboot
      def vm_reboot(vm)
        check_connection
        task_state = fog_op { |con| con.vm_reboot('instance_uuid' => vm.instance_uuid) }
      end

      def vm_power_off(vm)
        check_connection
        task_state = fog_op { |con| con.vm_power_off(\
                  'instance_uuid' => vm.instance_uuid, 'force'=>false, 'wait' => true) }
        #task_state #'success', 'running', 'queued', 'error'
      end

      def vm_power_on(vm)
        check_connection
        task_state = fog_op { |con| con.vm_power_on('instance_uuid' => vm.instance_uuid) }
      end

      def vm_create_disk(vm, disk, options={})
        check_connection
        info = { 'instance_uuid' => vm.instance_uuid,
          'vmdk_path' => disk.fullpath,
          'disk_size' => disk.size / DISK_SIZE_TIMES }
        info['thin_provision'] = disk.shared
        @logger.debug("Create disk :#{disk.fullpath} size:#{disk.size}MB")
        result = fog_op { |con| con.vm_create_disk(info) }
        # TODO add update disk and vm's info
      end

      # needs vm mobid to get the properties of this vm
      def update_vm_properties_by_vm_mob(vm)
        check_connection
        vm_properties = fog_op { |con| con.get_vm_properties(vm.mob) }
        update_vm_with_properties_string(vm, vm_properties)
      end

      ###################################################
      # query interface

      def get_vm_mob_ref_by_moid(vm_ref)
        check_connection
        fog_op { |con| con.get_vm_mob_ref_by_moid(vm_ref) }
      end

      def get_portgroups_by_dc_mob(dc_mob)
        check_connection
        fog_op { |con| con.get_portgroups_by_dc_mob(dc_mob) }
      end
      # get datacenter management object by a given path (with name)
      def get_dc_mob_ref_by_path(options={})
        check_connection
        fog_op { |con| con.get_dc_mob_ref_by_path(options) }
      end

      # get clusters belong to given datacenter
      def get_clusters_by_dc_mob(dc_mob_ref, options = {})
        check_connection
        fog_op { |con| con.get_clusters_by_dc_mob(dc_mob_ref, options) }
      end

      def ct_mob_ref_to_attr_hash(mob_ref, attr_s)
        check_connection
        fog_op { |con| con.ct_mob_ref_to_attr_hash(mob_ref, attr_s) }
      end

      #get cluster by a given path
      def get_cs_mob_ref_by_path(path, options = {})
        check_connection
        fog_op { |con| con.get_cs_mob_ref_by_path(path, options) }
      end

      #get hosts belong to a given cluster
      def get_hosts_by_cs_mob(cs_mob_ref, options = {})
        check_connection
        fog_op { |con| con.get_hosts_by_cs_mob(cs_mob_ref, options) }
      end

      #get resource pools belong to a given cluster
      def get_rps_by_cs_mob(cs_mob_ref, options={})
        check_connection
        fog_op { |con| con.get_rps_by_cs_mob(cs_mob_ref, options) }
      end

      #get datastore array belong to a given cluster
      def get_datastores_by_cs_mob(cs_mob_ref, options={})
        check_connection
        fog_op { |con| con.get_datastores_by_cs_mob(cs_mob_ref, options) }
      end

      #get datadstores accessible from a given host
      def get_datastores_by_host_mob(host_mob_ref, options={})
        check_connection
        fog_op { |con| con.get_datastores_by_host_mob(host_mob_ref, options) }
      end

      #get vm list provision from a given host
      def get_vms_by_host_mob(host_mob_ref, options={})
        check_connection
        fog_op { |con| con.get_vms_by_host_mob(host_mob_ref, options) }
      end

      #get disk list for a specific vm
      #return a array with hash as each hash {\'path\', \'size\', \'scsi_num\'}
      def get_disks_by_vm_mob(vm_mob_ref, options={})
        check_connection
        fog_op { |con| con.get_disks_by_vm_mob(vm_mob_ref, options) }
      end

      def get_ds_name_by_path(path)
        check_connection
        fog_op { |con| con.get_ds_name_by_path(path) }
      end

      def vm_update_network(vm)
        check_connection
        card = 0
        vm.network_config_json.each do |config_json|
          fog_op { |con| con.vm_update_network('instance_uuid' => vm.instance_uuid,
                                              'adapter_name' => "Network adapter #{card + 1}",
                                              'portgroup_name' => vm.network_res.port_group(card)) }

          @logger.debug("network json:#{config_json}")
          fog_op { |con| con.vm_config_ip('vm_moid' => vm.mob, 'config_json' => config_json) }
          card += 1
        end
      end

      def vm_set_ha(vm, enable)
        check_connection
        # default is enable
        try_num = 3
        return if enable
        try_num.times do |num|
          result = fog_op { |con| con.vm_disable_ha('vm_moid' => vm.mob) }
          if result['task_state'] == 'success'
            @logger.debug("vm:#{vm.name} disable ha success.")
            return
          end
          @logger.debug("vm:#{vm.name} disable ha failed and retry #{num+1} times.")
        end
      end

      def is_vm_in_ha_cluster(vm)
        check_connection
        fog_op { |con| con.is_vm_in_ha_cluster('vm_moid' => vm.mob) }
      end
      ###################################################
      # inner use functions
      def update_vm_with_properties_string(vm, vm_properties)
        vm.name             = vm_properties["name"]
        vm.mob              = vm_properties["mo_ref"] #moid
        vm.uuid             = vm_properties["uuid"]
        vm.instance_uuid    = vm_properties["instance_uuid"]
        vm.hostname         = vm_properties["hostname"]
        vm.operatingsystem  = vm_properties["operatingsystem"]
        vm.ip_address       = vm_properties["ipaddress"]
        vm.power_state      = vm_properties["power_state"]
        vm.connection_state = vm_properties["connection_state"]
        vm.tools_state      = vm_properties["tools_state"]
        vm.tools_version    = vm_properties["tools_version"]
        vm.is_a_template    = vm_properties["is_a_template"]
        nil
      end

      ###################################################
      # implement later
      def vm_attach_disk(vm, disk, options={})
      end

      def vm_detach_disk(vm, disk, options={})
      end

      def vm_delete_disk(vm, disk, options={})
      end

      def reconfigure_vm_cpu_mem(vm, config, options={})
      end

      def resize_disk(vm_cid, vmdk_path, new_size, options={})
      end
    end
  end
end

