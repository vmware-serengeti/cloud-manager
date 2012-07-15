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
      def_const_value :storage_service, {'require' => 'fog', 'obj' => 'InnerStorage'}
      def_const_value :enable_inner_storage_service, true
    end

    class InnerStorage < InnerServer
      class StorageServer
        attr_reader :host
        attr_reader :size
        attr_reader :value
        def initialize(host, size, value)
          @host = host
          @size = size
          @value = value
        end
      end

      def query_capacity(vmServers, info)
        info["hosts"]
      end

      def recommendation(vmServers, hostnames)
        index = 0
        Hash[hostnames.map { |host| [host, StorageServer.new(hosts[host], 1000, index += 1)] }]
      end

      def commission(vmServers)
        true
      end

      def decommission(vmServers)
      end
 
    end

    class ResourceStorage < CMService
      def name
        "storage"
      end

      def create_server(vm_spec)
        if config.enable_inner_storage_service
          @server = InnerStorage.new(vm_spec, self)
        else
          @server = cloud.create_service_obj(config.storage_service, vm_spec) # Currently, we only use the first engine
        end
        raise Serengeti::CloudManager::PluginException "Can not create service obj #{config.storage_service['obj']}" if @server.nil?
        @server
      end

      def deploy(vmServer)
        @server.create_volumes(vmServer)
      end

      def delete(vmServer)
        @server.delete_volumes(vmServer)
      end
    end

  end
end
