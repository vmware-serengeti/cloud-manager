require './cloud_item'
require 'fog'

module VHelper::CloudManager
  class Fog_adapter
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
      @connection.destroy
      @connection = nil
      @logger.info("Disconnect to cloud provider ")
    end

    def clone_vm(vm)
      raise "Do not login cloud server, please login first" if @connection.nil?
    
    end

    # TODO add option to force hard/soft reboot
    def reboot_vm(vm)
    end

    def vm_create_disk(vm, disk, options={})
    end

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
