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

      def init_with_vm_service(service, vm_spec)
        #@logger.debug("vmSpec:#{vm_spec.pretty_inspect}")
        vm = service.create_server(vm_spec)
        @plugin_vm[service.name] = vm
      end

      def vm(plugin_name)
        raise "Do not input correctly plugin name. #{plugin_name}" if !@plugin_vm.key?(plugin_name)
        @plugin_vm[plugin.name]
      end
    end

    class CMService < BaseObject
      attr_reader :hosts
      attr_reader :rps
      attr_reader :vm_groups
      attr_reader :placement_service

      def initialize(cloud)
        @cloud = cloud
      end

      def cloud
        @cloud
      end

      def init_self(info = {})
        dc_resource = info[:dc_resource]
        vm_groups = info[:vm_groups]
        placement_service = info[:place_service]

        raise "do not input vm_groups for CMService class" if vm_groups.nil?
        raise "do not input dc_resouce for CMService class" if dc_resource.nil?
        raise "do not input dc_resouce for CMService class" if placement_service.nil?

        @hosts = dc_resource.hosts
        @rps = dc_resource.resource_pools
        @vm_groups = vm_groups
        @placement_service = placement_service
        #logger.debug("cmserver:#{@hosts.pretty_inspect}")
        #logger.debug("dc:#{dc_resource.pretty_inspect}")
      end

      def create_server(vm_spec)
        raise "Should implement it in sub class"
      end

      def check_capacity(vmServers, hosts, options = {})
        info = { 'hosts' => hosts }
        result = @server.query_capacity(vmServers, info)
      end

      def evaluate_hosts(vmServers, hosts, options = {})
        @server.recommendation(vmServers, hosts)
        # TODO change result to wanted
      end

      def commit(vmServers, options = {})
        @server.commission(vmServers)
      end

      def discommit(vmServers, options = {})
        @server.decommission(vmServers)
      end

      def deploy(vmServers)
      end

      def delete(vmServers)
      end
    end

  end
end
