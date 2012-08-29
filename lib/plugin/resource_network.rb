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

# @version 0.5.1

module Serengeti
  module CloudManager

    class InnerNetwork < InnerServer
      class NetworkServer
        attr_reader   :host
        attr_accessor :spec
        attr_accessor :network_res
        attr_reader   :value
        def initialize(host, spec, value)
          @host = host
          @spec = spec
          @value = value
        end
      end

      def query_capacity(vmServers, info)
        vmServers.each do |spec|
          group_name = spec['vm_group_name']
          vm_group = vm_groups[group_name]

          #check portgroup
          unknown_pg = vm_group.network_res.not_existed_port_group(port_groups)
          if unknown_pg
            failed_vm_num = vm_group.instances - vm_group.vm_ids.size
            error_msg = "group #{vm_group.name}: can not find port group:#{unknown_pg} in vSphere."
            logger.error(error_msg)
            raise PlacementException,error_msg
          end
          #TODO add more networking check here
        end
        info['hosts']
      end

      def recommendation(vmServers, hostnames)
        index = 0
        Hash[hostnames.map { |host| [host, vmServers.map { |vm| NetworkServer.new(hosts[host], nil, index += 1) } ] }]
      end

      def commission(vmServers)
        net_res = vm_groups.first[1].network_res
        vmServers.each do |vm|
          vm.spec = [net_res.get_vm_network_json(0)]
          vm.network_res = net_res
        end
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
        super
        if config.enable_inner_network_service
          @server = InnerNetwork.new(self)
        else
          # Init fog storage_server
          info = cloud.get_provider_info()
          @server = cloud.create_service_obj(config.storage_service, info) # Currently, we only use the first engine
        end

      end

      def name
        "network"
      end

      def create_servers(vm_specs)
        inner_create_servers(vm_specs) {config.enable_inner_network_service }
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
