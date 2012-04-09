module VHelper::VSphereCloud
  class Resources
    RS_ATTR_TO_PROP = 0
    DS_ATTR_TO_PROP = 1
    HS_ATTR_TO_PROP = 2
    DK_ATTR_TO_PROP = 3
    VM_ATTR_TO_PROP = 4
    CS_ATTR_TO_PROP = 5
  end
  class Fog_dummy

    attr_accessor:logger

    DC_CONFIG_FILE = "../test/ut.dc.yaml"
    def initialize(logger)
      @logger = logger
      @logger.debug("Enter Fog_dummy")
      @debug_dc = YAML.load(File.open(DC_CONFIG_FILE))
      @logger.debug("Debug DC : #{@debug_dc}")
    end

    def login(vc_addr, vc_user, vc_pass)
      @logger.debug("Connect to #{vc_addr} and login, user:#{vc_user}, pass:#{vc_pass}")
      @vc_addr = vc_addr
    end

    def logout
      @logger.debug("Logout #{@vc_addr}")
    end

    def get_dc_node_by_path(dc_name, options={})
      @debug_dc.each do |dc|
        return dc if dc["name"] == dc_name
      end
      nil
    end

    def ct_mob_ref_to_attr_hash(mob, type, options={})
      return mob
    end

    def get_host_by_cs_mob(mob, options={})
      return mob["hosts"]
    end

    def get_rps_by_cs_mob(cluster_mob, options={})
      return cluster_mob["resource_pool"]
    end

    def get_cs_by_dc_mob(dc_mob, options={})
      return dc_mob["clusters"]
    end

    def get_datastores_by_cs_mob(cluster_mob, options={})
      return cluster_mob["datastores"]
    end

    def get_datastores_by_host_mob(host_mob, options={})
      return host_mob["datastores"]
    end

    def get_vms_by_host_mob(host_mob, options={})
      return host_mob["vms"]
    end

    def get_disk_from_vm_mob(vm_mob, options={})
      return vm_mob["disks"]
    end

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
