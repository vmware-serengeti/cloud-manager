module VHelper::CloudManager
  class FogDummy
    attr_reader:logger
    DC_CONFIG_FILE = "./spec/ut.dc.yaml"
    DC_WORK_FILE = "./spec/ut.dc-working.yaml"
    def initialize(logger)
      @logger = logger
      @ip_start = 2
      @logger.debug("Enter Fog_dummy")
      @debug_dc = YAML.load(File.open(DC_CONFIG_FILE))
      @work_dc = YAML.load(File.open(DC_WORK_FILE))
      @logger.debug("Debug DC : #{@debug_dc}")
      @lock = Mutex.new
      #@debugSleep = @debug_dc['debugSleep']
      @vm_prop = {}
    end

    def login(vc_addr, vc_user, vc_pass)
      @logger.debug("Connect to #{vc_addr} and login, user:#{vc_user}, pass:#{vc_pass}")
      @vc_addr = vc_addr
    end

    def logout
      @logger.debug("##Logout #{@vc_addr}")
    end

    def dummy_sleep(n)
      time = (rand * n) + n/2 + 1
      sleep(time.to_i)
    end

    def vm_destroy(vm)
      @logger.debug("destroy #{vm.name}")
      dummy_sleep(4)
      @vm_prop.delete(vm.name)
    end

    def vm_power_on(vm)
      @logger.debug("power on #{vm.name}")
      dummy_sleep(4)
      vm.power_state = "power on"
    end

    def clone_vm(vm, options={})
      @logger.debug("clone vm#{vm.name}")
      dummy_sleep(8)
      vm.power_state = (options[:power_on] == true)? "power on":"power off"
    end

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

    def update_vm_properties_by_vm_mob(vm)
      return vm if (@vm_prop.has_key?(vm.name))
      dummy_sleep(1)
      @lock.synchronize do
        #TODO read vm info from FILE later
        vm.ip_address = "1.1.1.#{@ip_start}"
        vm.mob = "vm_mob#{@ip_start}"
        @ip_start += 1
        @vm_prop[vm.name] = vm
      end
    end

    def get_dc_mob_ref_by_path(dc_name, options={})
      @debug_dc.each { |dc|
        return dc if dc["name"] == dc_name
      }
      nil
    end

    def ct_mob_ref_to_attr_hash(mob, type, options={}) mob end
    def get_hosts_by_cs_mob(mob, options={}) mob["hosts"] end
    def get_ds_name_by_path(path, options={}) "share-ds" end
    def get_rps_by_cs_mob(cluster_mob, options={}) cluster_mob["resource_pool"] end
    def get_clusters_by_dc_mob(dc_mob, options={}); dc_mob["clusters"]; end
    def get_datastores_by_cs_mob(cluster_mob, options={}); cluster_mob["datastores"]; end
    def get_datastores_by_host_mob(host_mob, options={}); host_mob["datastores"]; end
    def get_vms_by_host_mob(host_mob, options={}) host_mob["vms"] end
    def get_disks_by_vm_mob(vm_mob, options={}) vm_mob["disks"] end

    def vm_reboot(vm, options={})
    end

    def vm_create_disk(vm, disk, options={})
    end

    def vm_attach_disk(vm, disk, options={})
    end

    def vm_detach_disk(vm, disk, options={})
    end

    def vm_delete_disk(vm, disk, options={})
    end

    def reconfigure_vm_cpu_mem(vm, cpu, mem, options={})
    end

    def resize_disk(vm, disk, new_size, options={})
    end
  end
end
