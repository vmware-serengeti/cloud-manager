require './cloud_item'

module VHelper::VSphereCloud
  class Fog_adapter
    def initialize
    end

    def clone_vm(vm)
    end

    # TODO add option to force hard/soft reboot
    def reboot_vm(vm)
    end

    def vm_create_disk(vm, disk, options={})
    end

    def vm_attach_disk(vm, disk)
    end

    def vm_detach_disk(vm, disk)
    end

    def vm_delete_disk(vm, disk)
    end

    def reconfigure_vm_cpu_mem(vm, config)
    end

    def resize_disk(vm_cid, vmdk_path, new_size)
    end

    def generate_unique_name
      UUIDTools::UUID.random_create.to_s
    end

  end
end
