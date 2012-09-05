###############################################################################
#   Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
################################################################################

# @version 0.5.0
require 'fog'

module Serengeti
  module CloudManager
    class Config
      def_const_value :linked_clone, false
      def_const_value :client_connection_pool_size, 5
      def_const_value :ha_service_ready, true
    end

    class FogAdaptor < BaseObject
      DISK_SIZE_TIMES = 1
      include Serengeti::CloudManager::Parallel
      def initialize(cloud)
        @cloud = cloud
        @connection = nil
        @con_lock = Mutex.new
      end

      def cloud
        @cloud
      end


      def login()
        return unless @connection.nil?
        connect_list = Array.new(config.client_connection_pool_size)

        # Create Client pool for faster access vSphere
        @connection = {}
        @connection[:con] = []
        @connection[:ha_ft] = []
        @connection[:err] = []
        group_each_by_threads(connect_list, :callee => 'cloud login') do |con|
          begin
            connection = Fog::Compute.new(cloud.get_provider_info)
            @con_lock.synchronize { @connection[:con] << connection }
            if config.ha_service_ready
              ha_ft = Fog::Highavailability.new(cloud.get_provider_info)
              @con_lock.synchronize { @connection[:ha_ft] << ha_ft }
            end
          rescue => e
            @con_lock.synchronize { @connection[:err] << e if @connection }
          end
        end
        if @connection[:err].size > 0
          logger.error("#{@connection[:err].size} connections fail to login.\n "\
                        "error is:\n#{@connection[:err].join("\n")}")
          raise "#{@connection[:err].size} connections fail to login."
        end
        logger.debug("Use #{@connection[:con].size} channels to connect cloud service\n}")
      end

      def compute_op
        yield @con_lock.synchronize { @connection[:con].rotate!.first }
      end

      def ha_ft_op
        yield @con_lock.synchronize { @connection[:ha_ft].rotate!.first }
      end

      def logout
        @con_lock.synchronize do
          unless @connection.nil?
            @connection.each { |con| }#con.close }
            #TODO destroy @connection
          end
        end
        logger.info("Disconnect from cloud provider ")
      end

      def vm_clone(vm, options={})
        check_connection
        linked_clone = config.linked_clone || false
        info = {
          'vm_moid' => vm.spec['template_id'],
          'name' => vm.name,
          'wait' => 1,
          'linked_clone' => linked_clone, # vsphere 5.0 has a bug with linked clone over 8 hosts, be conservative
          'datastore_moid' => vm.sys_datastore_moid,
          'rp_moid' => vm.resource_pool_moid,
          'host_moid' => vm.host_mob,
          'folder_path' => vm.spec['vm_folder_path'],
          'power_on' => false,
          'cpu' => vm.spec['cpu'],
          'memory' => vm.spec['req_mem'],
        }
        logger.debug("clone info: #{info.pretty_inspect}")
        result = compute_op { |con| con.vm_clone(info) }
        logger.debug("after clone: result :#{result} ")
        update_vm_with_properties_string(vm, result["vm_attributes"])
      end

      def check_connection
        raise "Do not login cloud server, please login first" if @connection.nil?
      end

      # TODO add vm_xxxx return state checking
      def vm_destroy(vm)
        check_connection
        task_state = compute_op { |con| con.vm_destroy('instance_uuid' => vm.instance_uuid) }
      end

      def vm_reboot(vm)
        check_connection
        task_state = compute_op { |con| con.vm_reboot('instance_uuid' => vm.instance_uuid) }
      end

      def vm_power_off(vm)
        check_connection
        task_state = compute_op { |con| con.vm_power_off(\
                  'instance_uuid' => vm.instance_uuid, 'force'=>false, 'wait' => true) }
      end

      def vm_power_on(vm)
        check_connection
        task_state = compute_op { |con| con.vm_power_on('instance_uuid' => vm.instance_uuid) }
      end

      def vm_create_disk(vm, disk, options={})
        check_connection
        info = { 'instance_uuid' => vm.instance_uuid,
          'vmdk_path' => disk.fullpath,
          'disk_size' => disk.size / DISK_SIZE_TIMES }
        info['provison_type'] = (disk.shared && disk.type == 'data') ? 'thin' : nil
        logger.debug("Create disk :#{disk.fullpath} size:#{disk.size}MB, type:#{info['provison_type']}")
        result = compute_op { |con| con.vm_create_disk(info) }
      end

      # Update vm's network configuration
      def vm_update_network(vm, options = {})
        check_connection
        card = 0
        vm.network_config_json.each do |config_json|
          compute_op { |con| con.vm_update_network('instance_uuid' => vm.instance_uuid,
                                              'adapter_name' => "Network adapter #{card + 1}",
                                              'portgroup_name' => vm.network_res.port_group(card)) }

          logger.debug("network json:#{config_json}") if config.debug_networking
          compute_op { |con| con.vm_config_ip('vm_moid' => vm.mob,
                                          'config_json' => config_json) }
          card += 1
        end
      end

      ##################################################
      # High Availability Interface
      def vm_set_ha(vm, enable)
        check_connection
        # default is enable
        try_num = 3
        return if enable
        try_num.times do |num|
          if config.ha_service_ready
            result = ha_ft_op { |ha| ha.vm_disable_ha('vm_moid' => vm.mob) }
          else
            result = compute_op { |con| con.vm_disable_ha('vm_moid' => vm.mob) }
          end
          if result['task_state'] == 'success'
            logger.debug("vm:#{vm.name} disable ha success.")
            return
          end
          logger.debug("vm:#{vm.name} disable ha failed and retry #{num+1} times.")
        end
      end

      def is_vm_ft_primary(vm)
        check_connection
        return ha_ft_op { |ha| ha.is_vm_ft_primary('vm_moid' => vm.mob) }
      end

      def is_vm_in_ha_cluster(vm)
        check_connection
        compute_op { |con| con.is_vm_in_ha_cluster('vm_moid' => vm.mob) }
      end

      def vm_set_ft(vm, enable)
        check_connection
        return if !config.ha_service_ready
        result = {}
        result['task_state'] = 'running'
        enable_string = (enable)? 'Enable': 'Disable'
        loop do
          if enable
            result = ha_ft_op { |ft| ft.vm_enable_ft('vm_moid' => vm.mob) }
          else
            result = ha_ft_op { |ft| ft.vm_disable_ft('vm_moid' => vm.mob) }
          end
          logger.debug("FT result: #{result.pretty_inspect}")
          case result['task_state']
          when 'running'
            sleep(4)
            logger.debug("Waiting FT work")
          when 'error'
            raise "FT failed #{result.pretty_inspect}"
            break
          when 'success'
            logger.debug("#{enable_string} FT success!!")
            break
          end
        end
      end

      ###############################################
      # Get/Set interface
      # get hash value from ref object
      def ct_mob_ref_to_attr_hash(mob_ref, attr_s)
        check_connection
        compute_op { |con| con.ct_mob_ref_to_attr_hash(mob_ref, attr_s) }
      end

      # needs vm mobid to get the properties of this vm
      def get_vm_properties_by_vm_mob(vm)
        check_connection
        vm_properties = compute_op { |con| con.get_vm_properties(vm.mob) }
        update_vm_with_properties_string(vm, vm_properties)
      end


      def get_vm_mob_ref_by_moid(vm_ref, dc_mob)
        check_connection
        compute_op { |con| con.get_vm_mob_ref_by_moid(vm_ref) }
      end

      def get_portgroups_by_dc_mob(dc_mob)
        check_connection
        compute_op { |con| con.get_portgroups_by_dc_mob(dc_mob) }
      end

      # get datacenter management object by a given path (with name)
      def get_dc_mob_ref_by_path(options={})
        check_connection
        compute_op { |con| con.get_dc_mob_ref_by_path(options) }
      end

      # get clusters belong to given datacenter
      def get_clusters_by_dc_mob(dc_mob_ref, options = {})
        check_connection
        compute_op { |con| con.get_clusters_by_dc_mob(dc_mob_ref, options) }
      end

      #get cluster by a given path
      def get_cs_mob_ref_by_path(path, options = {})
        check_connection
        compute_op { |con| con.get_cs_mob_ref_by_path(path, options) }
      end

      #get hosts belong to a given cluster
      def get_hosts_by_cs_mob(cs_mob_ref, options = {})
        check_connection
        compute_op { |con| con.get_hosts_by_cs_mob(cs_mob_ref, options) }
      end

      #get resource pools belong to a given cluster
      def get_rps_by_cs_mob(cs_mob_ref, options={})
        check_connection
        compute_op { |con| con.get_rps_by_cs_mob(cs_mob_ref, options) }
      end

      #get datastore array belong to a given cluster
      def get_datastores_by_cs_mob(cs_mob_ref, options={})
        check_connection
        compute_op { |con| con.get_datastores_by_cs_mob(cs_mob_ref, options) }
      end

      #get datadstores accessible from a given host
      def get_datastores_by_host_mob(host_mob_ref, options={})
        check_connection
        compute_op { |con| con.get_datastores_by_host_mob(host_mob_ref, options) }
      end

      #get vm list provision from a given host
      def get_vms_by_host_mob(host_mob_ref, options={})
        check_connection
        compute_op { |con| con.get_vms_by_host_mob(host_mob_ref, options) }
      end

      #get disk list for a specific vm
      #return a array with hash as each hash {\'path\', \'size\', \'scsi_num\'}
      def get_disks_by_vm_mob(vm_mob_ref, options={})
        check_connection
        compute_op { |con| con.get_disks_by_vm_mob(vm_mob_ref, options) }
      end

      def get_ds_name_by_path(path)
        check_connection
        compute_op { |con| con.get_ds_name_by_path(path) }
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

