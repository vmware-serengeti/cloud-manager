###############################################################################
#    Copyright (c) 2012 VMware, Inc. All Rights Reserved.
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

# @since serengeti 0.5.0
# @version 0.5.0
# @author haiyu wang

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
