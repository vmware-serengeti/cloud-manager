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
      def_const_value :ha_service, {'require' => '', 'obj' => 'InnerFT'}
      def_const_value :enable_inner_ha_service, true
    end

    class InnerHA < InnerServer
      class HAServer
        attr_reader :host
        attr_reader :value
        def initialize(host, value)
          @host = host
          @value = value
        end
      end

      def initialize(cm_server)
        super
      end

      def query_capacity(vmServers, info)
        info['hosts']
      end

      def recommendation(vmServers, hostnames)
        index = 0
        Hash[hostnames.map { |host| [host, vmServers.map { |vm| HAServer.new(hosts[host], index+=1) } ] } ]
      end

      def commission(vm_server)
        true
      end

      def decommission(vm_server)
      end

    end

    class ResourceHA < CMService
      def initialize(cloud)
        super
        if config.enable_inner_ha_service
          @server = InnerHA.new(self)
        else
          # Init fog storage_server
          info = cloud.get_provider_info()
          @server = cloud.create_service_obj(config.ha_service, info)
        end
      end

      def name
        "ha"
      end

      def create_servers(vm_specs)
        inner_create_servers(vm_specs) {config.enable_inner_ha_service }
      end

      def delete(vmServer)
        @server.decommission(vmServer)
      end
    end
 
  end
end
