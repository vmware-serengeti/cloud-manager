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
    class Config
      def_const_value :ft_service, {'require' => '', 'obj' => 'InnerFT'}
      def_const_value :enable_inner_ft_service, true
    end

    class InnerFT < InnerServer
      class FTServer
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
        hostnames = info["hosts"]
        match_host_names = nil
        vmServers.each do |spec|
          next if spec['ha'] != 'ft'
          error_msg = []
          error_msg << "vm #{spec['name']}, FT could not support more than one vCpu." if spec['cpu'].to_i > 1
          error_msg << "vm #{spec['name']}, FT should use shared system storage." if spec['system_shared'] == false
          error_msg << "vm #{spec['name']}, FT should use shared data storage." if spec['data_shared'] == false
          raise PlacementException, error_msg.join if !error_msg.empty?
        end
        hostnames
      end

      def recommendation(vmServers, hostnames)
        index = 0
        Hash[hostnames.map { |host| [host, vmServers.map { |vm| FTServer.new(hosts[host], index+=1) } ] } ]
      end

      def commission(vm_server)
        true
      end

      def decommission(vm_server)
      end
    end
 
    class ResourceFT < CMService
      def initialize(cloud)
        super
        if config.enable_inner_ft_service
          @server = InnerFT.new(self)
        else
          # Init fog storage_server
          info = cloud.get_provider_info()
          @server = cloud.create_service_obj(config.ft_service, info)
        end
      end

      def name
        "ft"
      end

      def create_servers(vm_specs)
        inner_create_servers(vm_specs) {config.enable_inner_ft_service }
      end

      def delete(vmServer)
        @server.decommission(vmServer)
      end
    end
  end
end
