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
      def_const_value :enable_inner_compute_service, true
      def_const_value :compute_service_fault_test, false
      def_const_value :compute_support_memory_overcommit, false
      def_const_value :compute_service, {'require' => nil, 'obj' => 'InnerCompute'}
    end

    class InnerCompute < InnerServer
      def total_memory(vmServers)
        @total_memory = 0
        #logger.debug("specs:#{vm_specs.pretty_inspect}")
        memory = vmServers.map { |spec| spec['req_mem'] }
        memory.each { |m| @total_memory += m.to_i }
        @total_memory
      end

      def initialize(cm_server)
        super
      end

      class ComputeServer
        attr_reader :host
        attr_reader :total_memory
        attr_reader :value
        def initialize(host, total_memory, value)
          @host = host
          @total_memory = total_memory
          @value = value
        end
      end

      def query_capacity(vmServers, info)
        #logger.debug("hosts: #{hosts.pretty_inspect}")
        if config.compute_support_memory_overcommit
          total_memory(vmServers)
          logger.debug("query hosts: #{info['hosts']} total_mem:#{@total_memory}")
          return info['hosts'].select { |h| hosts[h].real_free_memory > @total_memory if hosts.key?(h) }
        else
          return info['hosts']
        end
      end

      def recommendation(vmServers, hostnames)
        #logger.debug("recommend hosts: #{hosts.pretty_inspect}")
        sort_result = hostnames.sort { |x,y| hosts[y].real_free_memory <=> hosts[x].real_free_memory }
        index = 0
        result = Hash[sort_result.map { |host| [host, vmServers.map { |vm| ComputeServer.new(hosts[host], @total_memory, index+=1) } ] } ]
        if config.compute_service_fault_test
          result.each { |host, value| result[host] = nil }
        end
        result
      end

      def commission(vm_server)
        logger.debug("compute vm_server: #{vm_server.first.pretty_inspect}")
        if config.compute_support_memory_overcommit
          vm_server.first.host.unaccounted_memory += vm_server.first.total_memory
        end
        true
      end

      def decommission(vm_server)
        if config.compute_support_memory_overcommit
          vm_server.first.host.unaccounted_memory -= vm_server.first.total_memory
        end
      end
    end

    class ResourceCompute < CMService
      def initialize(cloud)
        super
        if config.enable_inner_compute_service
          @server = InnerCompute.new(self)
        else
          # Init fog storage_server
          info = cloud.get_provider_info()
          @server = cloud.create_service_obj(config.storage_service, info) # Currently, we only use the first engine
        end
      end

      def name
        "compute"
      end

      def create_servers(vm_specs)
        inner_create_servers(vm_specs) {config.enable_inner_compute_service }
      end

      def deploy(vmServer)
      end

      def delete(vmServer)
        @server.decommission(vmServer)
      end

    end
  end
end

