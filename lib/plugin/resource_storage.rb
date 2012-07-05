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

    class InnerStorage < BaseObject
      def initialize(vm_spec)
      end

      def get_info_from(dc_resource)
        @dc = dc_resource
      end

      def query_capacity(vmServers, info)
      end

      def recommendation(vmServers, hosts)
      end

      def commission(vmServers)
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
          @storage = InnerStorage.new(vm_spec)
        else
          @storage = cloud.create_service_obj(config.storage_service, vm_spec) # Currently, we only use the first engine
        end
        raise Serengeti::CloudManager::PluginException "Can not create service obj #{config.storage_service['obj']}" if @storage.nil?
        @storage
      end

      def check_capacity(vmServers, hosts, options = {})
        info = {'hosts' => hosts.map {|h|h.host_name } }
        @storage.query_capacity(vmServers, info)
      end

      def calc_values(vmServers, hosts, options = {})
        @storage.recommendation(vmServers, hosts)
        # TODO change result to wanted
      end

      def commit(vmServers, host, options = {})
        @storage.commission(vmServers)
      end

      def discommit(vmServers, options = {})
        @storage.decommission(vmServers)
      end

      def deploy(vmServer)
        @storage.create_volumes(vmServer)
      end

      def delete(vmServer)
        @storage.delete_volumes(vmServer)
      end
    end

  end
end
