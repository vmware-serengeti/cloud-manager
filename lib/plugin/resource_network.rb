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

    class InnerNetwork < BaseObject
      class NetworkServer
        attr_reader :host
        attr_reader :spec
        attr_reader :value
        def initialize(host, spec, value)
          @host = host
          @spec = spec
          @value = value
        end
      end

      def initialize(vm_spec, cm_server)
        @cm_server = cm_server
        @vm_spec = vm_spec
      end

      def hosts; @cm_server.hosts; end
      def rps; @cm_server.rps; end
      def dc_resource; @cm_server.dc_resource; end
      def vm_groups; @cm_server.vm_groups; end


      def query_capacity(vmServers, info)
        info['hosts']
      end

      def recommendation(vmServers, hostnames)
        index = 0
        Hash[hostnames.map { |host| [host, NetworkServer.new(hosts[host], nil, index += 1)] }]
      end

      def commission(vmServer)
        true
      end

      def decommission(vmServer)
      end
 
    end

    class Config
      def_const_value :enable_inner_network_service, true
      def_const_value :network_service, {'require' => '', 'obj' => 'InnerNetwork'}
    end

    class ResourceNetwork < CMService
      def initialize(cloud)
        @cloud = cloud
      end

      def name
        "network"
      end

      def create_server(vm_spec)
        if config.enable_inner_network_service
          @server = InnerNetwork.new(vm_spec, self)
        else
          @server = cloud.create_service_obj(config.network_service, vm_spec) 
        end
        raise Serengeti::CloudManager::PluginException, "Can not create service obj #{config.network_service['obj']}" if @server.nil?
        @server
      end

      def deploy(vmServer)
        @server.create(vmServer)
      end

      def delete(vmServer)
        @server.delete(vmServer)
      end
    end

  end
end
