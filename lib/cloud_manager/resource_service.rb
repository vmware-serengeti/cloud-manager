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
    class VmServer
      def initialize
        @plugin_vm = {}
        @logger = Serengeti::CloudManager.logger
      end

      def init_with_vm_service(service, vmSpec)
        @logger.debug("vmSpec:#{vmSpec.pretty_inspect}")
        vm = service.create_server(vmSpec)
        @plugin_vm[service.name] = vm
      end

      def vm(plugin_name)
        raise "Do not input correctly plugin name. #{plugin_name}" if !@plugin_vm.key?(plugin_name)
        @plugin_vm[plugin.name]
      end
    end

    class CMService < BaseObject
      def initialize(cloud)
        @cloud = cloud
      end

      def cloud
        @cloud
      end

      def check_resource_valid(test)
        nil
      end

      def create_server(vm_spec)
        nil
      end

      def init_self(placement_service)
        @placement_service = placement_service
      end

      def get_info_from_dc_resource(dc_resource)
        nil
      end

      def check_capacity(vmServers, hosts, options = {})
      end

      def calc_values(vmServers, hosts, options = {})
      end

      def commit(vmServers, host, options = {})
      end

      def discommit(vmServers, options = {})
      end

      def deploy(vmServers)
      end

      def delete(vmServers)
      end
    end

  end
end
