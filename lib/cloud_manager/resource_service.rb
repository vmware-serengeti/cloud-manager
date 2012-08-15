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
    class VmServer < BaseObject
      attr_accessor :error_code
      attr_accessor :error_msg

      def initialize
        @plugin_vm = {}
      end

      def init_with_vm_service(service, vm_specs)
        #logger.debug("vmSpec:#{vm_spec.pretty_inspect}")
        vm = service.create_servers(vm_specs)
        @plugin_vm[service.name] = {}
        @plugin_vm[service.name][:vm] = vm
      end

      def vm(plugin_name)
        raise "Do not input correctly plugin name. #{plugin_name}" if !@plugin_vm.key?(plugin_name)
        @plugin_vm[plugin_name][:vm]
      end

      def assigned(plugin_name, selected_host, output_vm)
        raise "Do not input correctly plugin name. #{plugin_name}" if !@plugin_vm.key?(plugin_name)
        @plugin_vm[plugin_name][:output_vm] = output_vm
        @plugin_vm[plugin_name][:select_host] = selected_host
      end
    end

    class InnerServer < BaseObject
      def hosts; @cm_server.hosts; end
      def rps; @cm_server.rps; end
      def dc_resource; @cm_server.dc_resource; end
      def vm_groups; @cm_server.vm_groups; end
      def clusters; @cm_server.clusters; end
      def port_groups; @cm_server.port_groups; end

      def initialize(cm_server)
        @cm_server = cm_server
      end

      def query_capacity(vmServers, info)
        info['hosts']
      end

      def commission(vm_server)
        true
      end

      def decommission(vm_server)
      end


    end

    class CMService < BaseObject
      attr_reader :hosts
      attr_reader :rps
      attr_reader :vm_groups
      attr_reader :placement_service
      attr_reader :clusters
      attr_reader :port_groups

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
        @clusters = dc_resource.clusters
        @port_groups = dc_resource.port_group
      end

      def inner_create_servers(vm_specs)
        if yield
          return vm_specs #InnerServers
        else
          return vm_specs.map { |vm_spec| Fog::Storage::Vsphere::Shared::VM.new(vm_spec) }
        end
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
        logger.debug("Call #{name} commission")
        @server.commission(vmServers)
      end

      def discommit(vmServers, options = {})
        @server.decommission(vmServers)
      end

      def deploy(vmServers)
      end

      def delete(vmServers)
      end

      def method_missing(m, *args, &block)
        @server.send(m, *args)
      end
    end

  end
end
