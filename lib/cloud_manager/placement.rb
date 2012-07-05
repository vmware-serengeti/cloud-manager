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

# @since serengeti 0.5.1
# @version 0.5.1

module Serengeti
  module CloudManager
    class Config
      def_const_value :vm_sys_disk_size     , 05 * 1024 #MB
      def_const_value :min_disk_size        , 01 * 1024 #MB
      def_const_value :remainder_disk_size  , 16 * 1024 #MB

      def_const_value :swap_disk_size     , [2048, 4096, 16384, 65536]
      def_const_value :swap_mem_size      , [1024, 2048, 4096, 8192]
      def_const_value :max_swap_disk_size , 12288

      def_const_value :vm_place_swap_disk , true
      def_const_value :vm_sys_disk_colocated_with_data_disk, true
    end

    class Placement
      def initialize(cloud)
        @cloud = cloud 
      end

      def gen_cluster_vm_name(group_name, num)
        @cloud.gen_cluster_vm_name(group_name, num)
      end

      def placement_init(place_service, dc_resource)
        @place_service = place_service
        @dc_resource = dc_resource
      end

      def config
        Serengeti::CloudManager.config 
      end

      def set_placement_error_msg(msg)
        @place_service.set_placement_error_msg(msg)
      end

    end

  end
end
