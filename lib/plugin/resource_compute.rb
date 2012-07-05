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
      def_const_value :enable_inner_compute_service, true
      def_const_value :compute_service, {'require' => nil, 'obj' => 'InnerCompute'}
    end

    class InnerCompute < BaseObject
      def initialize(vm_spec)
      end

      def get_info_from_dc_resource(dc_resource)
        @dc = dc_resource
      end

      def query_capacity(vmServers, info)
        info['hosts']
      end

      def recommendation(vmServers, hosts)
        sort_result = hosts.sort { |x,y| x.real_free_memory <=> y.real_free_memory }
      end

      def commission(vmServers)
      end

      def decommission(vmServers)
      end
    end

    class ResourceCompute < CMService
      def name
        "compute"
      end

      def create_server(vm_spec)
        @compute = cloud.create_service_obj(config.compute_service, vm_spec) # Currently, we only use the first engine
        raise Serengeti::CloudManager::PluginException "Can not create service obj #{config.compute_service['obj']}" if @compute.nil?
        @compute
      end

      def check_capacity(vmServers, hosts, options = {})
        info = { 'hosts' => hosts }
        result = @compute.query_capacity(vmServers, info)
      end

      def calc_values(vmServers, hosts, options = {})
        @compute.recommendation(vmServers, hosts)
        # TODO change result to wanted
      end

      def commit(vmServers, host, options = {})
        @compute.commission(vmServers)
      end

      def discommit(vmServers, options = {})
        @compute.decommission(vmServers)
      end

      def deploy(vmServer)
      end

      def delete(vmServer)
        @compute.decommission(vmServer)
      end

    end 
  end
end

