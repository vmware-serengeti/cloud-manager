require './client_fog'
require '../test/fog_dummy'
module VHelper::VSphereCloud 
  class ClientFactory
    def self.create(name, logger)
      case name
      when "ut"
        return Fog_dummy.new(logger)
      when "fog"
        return fog_adapter.new
      else
        return Client_dummy.new(logger)
      end
    end
  end

  class Client_dummy
    #TODO add dummy functions here
    def ct_mob_ref_to_attr_hash(mob, type, options={})
    end 

    def get_host_by_cs_mob(mob, options={})
    end

    def get_rps_by_cs_mob(cluster_mob, options={})
    end 

    def get_cs_by_dc_mob(dc_mob, options={})
    end 

    def get_vms_by_host_mob(vm_mob, options={})
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
