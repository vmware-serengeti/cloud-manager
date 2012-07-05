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
      def initialize(vm_spec)
      end

      def get_info(dc_resource)
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
          @network = InnerNetwork.new(vm_spec)
        else
          @network = cloud.create_service_obj(config.network_service, vm_spec) 
        end
        raise Serengeti::CloudManager::PluginException, "Can not create service obj #{config.network_service['obj']}" if @network.nil?
        @network
      end

      def check_capacity(vmServers, hosts, options = {})
        if config.enable_inner_network_service
          info = {'hosts' => hosts }
        else
          info = {'hosts' => hosts.keys}
        end
        @network.query_capacity(vmServers, info)
      end

      def calc_values(vmServers, hosts, options = {})
        @network.recommendation(vmServers, hosts)
        # TODO change result to wanted
      end

      def commit(vmServers, host, options = {})
        @network.commission(vmServers)
      end

      def discommit(vmServers, options = {})
        @network.decommission(vmServers)
      end

      def deploy(vmServer)
        @network.create(vmServer)
      end

      def delete(vmServer)
        @network.delete(vmServer)
      end
    end


    end

  end
end
