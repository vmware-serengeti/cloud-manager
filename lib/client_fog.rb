require './cloud_item'
require '../../fog/lib/fog'

module VHelper::CloudManager
  class FogAdapter
    attr_reader :logger
    def initialize(logger)
      @logger = logger
      @connection = nil
    end

    def login(vc_addr, vc_user, vc_pass)
      if @connection.nil?
        cloud_server = 'vsphere'
        info = {:provider => cloud_server,
            :vsphere_server => vc_addr,
            :vsphere_username => vc_user,
            :vsphere_password => vc_pass,
            :vsphere_expected_pubkey_hash => '1bf5e752376a33c278ed2d2ee7e1fed8739ee7f24c233b89fed2fe69535646db'}

          connection = Fog::Compute.new(info)
          @logger.info("Connect to cloud provider: #{cloud_server}")
          @connection = connection
      end
    end

    def logout
      unless @connection.nil?
        @connection.destroy
      end
      @connection = nil
      @logger.info("Disconnect to cloud provider ")
    end

    def clone_vm(vm)
      raise "Do not login cloud server, please login first" if @connection.nil?
      info = {
        'path'=>vm.template_id,
        'name'=>vm.name,
        'wait'=> 1,
        'linked_clone'=>true,
        'datastore_moid' => vm.sys_datastore.mob, #'datastore-460',
        'rp_moid' => vm.host.resource_pool.mob, #'resgroup-509',
        'host_moid' => vm.host.mob, #'host-456'
      }
      vm_ref, vm_attributes, task_ref = @connection.vm_clone(info)
      update_vm_with_properties(vm, vm_attributes)
      # TODO add update vm's info
    end

    # TODO add option to force hard/soft reboot
    def vm_reboot(vm)
      raise "Do not login cloud server, please login first" if @connection.nil?
      task_state = @connection.vm_reboot(:instance_uuid => vm.instance_uuid)
    end

    def vm_power_off(vm)
      raise "Do not login cloud server, please login first" if @connection.nil?
      task_state = @connection.vm_power_off(:instance_uuid => vm.instance_uuid)
      #task_state #'success', 'running', 'queued', 'error'
    end

    def vm_power_on(vm)
      raise "Do not login cloud server, please login first" if @connection.nil?
      task_state = @connection.vm_power_on(:instance_uuid => vm.instance_uuid)
    end

    def vm_create_disk(vm, disk, options={})
      raise "Do not login cloud server, please login first" if @connection.nil?
      info = {:instance_uuid => vm.instance_uuid, :vmdk_path => disk.fullpath, :disk_size => disk.size}
      vm_ref, vm_attributes, vm_dev_number_increase = @connection.vm_create_disk(info)
      return vm_dev_number_increase
      # TODO add update disk and vm's info
    end

    # needs vm mobid to get the properties of this vm
    def update_vm_properties_by_vm_mob(vm_mob)
      raise "Do not login cloud server, please login first" if @connection.nil?
      vm_properties = @connection.get_vm_properties(vm_mob)
      update_vm_with_properties(vm, vm_properties)
      #TODO add update vm spec info
    end

    ###################################################
    # query interface
 
    # get datacenter management object by a given path (with name)
    def get_dc_mob_ref_by_path(options={})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_dc_mob_ref_by_path(options)
    end

    # get clusters belong to given datacenter
    def get_clusters_by_dc_mob(dc_mob_ref, options = {})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_clusters_by_dc_mob(dc_mob_ref, options)
    end


    #get cluster by a given path
    def get_cs_mob_ref_by_path(path,options = {})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_cs_mob_ref_by_path(path, options)
    end

    #get hosts belong to a given cluster
    def get_hosts_by_cs_mob(cs_mob_ref, options = {})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_hosts_by_cs_mob(cs_mob_ref, options)
    end

    #get resource pools belong to a given cluster
    def get_rps_by_cs_mob(cs_mob_ref, options={})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_rps_by_cs_mob(cs_mob_ref, options)
    end

    #get datastore array belong to a given cluster
    def get_datastores_by_cs_mob(cs_mob_ref, options={})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_datastores_by_cs_mob(cs_mob_ref, options)
    end

    #get datadstores accessible from a given host
    def get_datastores_by_host_mob(host_mob_ref,options={})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_datastores_by_host_mob(host_mob_ref,options)
    end

    #get vm list provision from a given host
    def get_vms_by_host_mob(host_mob_ref,options={})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_vms_by_host_mob(host_mob_ref,options)
    end

    #get disk list for a specific vm
    #return a array with hash as each hash {\'path\', \'size\', \'scsi_num\'}
    def get_disks_by_vm_mob(vm_mob_ref,options={})
      raise "Do not login cloud server, please login first" if @connection.nil?
      return @connection.get_disks_by_vm_mob(vm_mob_ref,options)
    end

    ###################################################
    # inner use functions
    def update_vm_with_properties(vm, vm_properties)
      vm.name             = vm_properties[:name]
      vm.mob              = vm_properties[:mo_ref] #moid
      vm.uuid             = vm_properties[:uuid]
      vm.instance_uuid    = vm_properties[:instance_uuid]
      vm.hostname         = vm_properties[:hostname]
      vm.operatingsystem  = vm_properties[:operatingsystem]
      vm.ip_address       = vm_properties[:ipaddress]
      vm.power_state      = vm_properties[:power_state]
      vm.connection_state = vm_properties[:connection_state]
      vm.hypervisor       = vm_properties[:hypervisor]
      vm.tools_state      = vm_properties[:tools_state]
      vm.tools_version    = vm_properties[:tools_version]
      vm.is_a_template    = vm_properties[:is_a_template]
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

=begin
(1) For VM
VM_ATTR_TO_PROP = {
  :id,
  :name,
  :mo_ref, #moid
  :uuid,
  :instance_uuid,
  :hostname,
  :operatingsystem,
  :ipaddress,
  :power_state,
  :connection_state,
  :hypervisor,
  :tools_state,
  :tools_version,
  :is_a_template
}

#(2) For Datacenter
DC_ATTR_TO_PROP = {
  :id,
  :name,
  :mo_ref, #moid
}

#3 Cluster
CS_ATTR_TO_PROP = {
  :id,
  :name,
  :mo_ref, #moid
  :eff_mem,
  :max_mem
}

#4 Datastore
DS_ATTR_TO_PROP = {
  :id,
  :name,
  :mo_ref, #moid
  :freeSpace,
  :maxSpace,
}

#5 Resource_pool
RP_ATTR_TO_PROP = {
  :id,
  :name,
  :mo_ref, #moid
  :limit_cpu,
  :limit_mem,
  :shares,
  :used_cpu,
  :host_used_mem,
  :guest_used_mem
}

#6 For Host
HS_ATTR_TO_PROP = {
  :id,
  :name,
  :mo_ref, #moid
  :total_memory,
  :cpu_num,
  :cpu_mhz,
  :used_cpu,
  :used_mem
}
=end

