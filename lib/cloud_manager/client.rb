module Serengeti
  module CloudManager

    class ClientFactory
      def self.create(name)
        case name
        when "ut"
          return FogDummy.new
        when "fog"
          return FogAdapter.new
        else
          return ClientDummy.new
        end
      end
    end

    class ClientDummy
      #TODO add dummy functions here
      def ct_mob_ref_to_attr_hash(mob, type, options={})
      end

      def get_host_by_cs_mob(mob, options={})
      end

      def get_rps_by_cs_mob(cluster_mob, options={})
      end

      def get_clusters_by_dc_mob(dc_mob, options={})
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
end
