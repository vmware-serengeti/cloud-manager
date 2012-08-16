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

# @since serengeti 0.5.1
# @version 0.5.1

module Serengeti
  module CloudManager
    class Config
      def_const_value :vm_sys_disk_size     , 05 * 1024 #MB
    end

    class Placement < BaseObject
      def initialize(cloud)
        @cloud = cloud
      end

      include Serengeti::CloudManager::Utils

      def clean_cluster(vm_groups_input, existed_vms)
        nil
      end

      def pre_placement_cluster(vm_groups, existed_vms)
        delete_vms = []

        #remove unused vm
        existed_vms.each_value do |vm|
          result = parse_vm_from_name(vm.name)
          vm_group = vm_groups[result['group_name']]
          next if vm_group.nil?
          delete_vms << vm if result['num'].to_i >= vm_group.instances.to_i
        end

        return nil if delete_vms.empty?
        logger.debug("remove out of cluster's VMs:#{delete_vms.map {|vm| vm.name}}")
        
        {:action => [ {'act'=>'group_delete', 'group' => delete_vms} ],
         :rollback => 'fetch_info'}
      end

      def placement_init(place_service, dc_resource)
        @place_service = place_service
        @dc_resource = dc_resource
      end

      def set_placement_error_msg(msg)
        @place_service.set_placement_error_msg(msg)
      end

    end

  end
end
