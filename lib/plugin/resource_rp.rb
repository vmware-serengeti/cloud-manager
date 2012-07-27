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
      def_const_value :rp_service, {'require' => '', 'obj' => 'InnerRP'}
      def_const_value :enable_inner_rp_service, true
    end

    class InnerRP < InnerServer
      class RPServer
        attr_reader :host
        attr_reader :size
        attr_reader :value
        attr_reader :rp
        def initialize(host, rp, size, value)
          @host = host
          @rp = rp
          @size = size
          @value = value
        end
      end

      def initialize(cm_server)
        super
        @rp_group = {}
        @inited = false
      end

      def is_suitable_resource_pool?(rp, mem)
        logger.debug("limit:#{rp.limit_mem}, real_free:#{rp.real_free_memory}, req:#{mem}")
        if rp.limit_mem != -1 && (rp.real_free_memory < mem)
          logger.debug("rp:#{rp.name} has not enough memory to vm_group")
          return false
        end
        true
      end

      def suitable_host_with_rp(vm_group, mem)
        place_rps = vm_group.req_rps.map do |cluster_name, rps|
          rps.map { |rp_name| clusters[cluster_name].resource_pools[rp_name] if clusters.key?(cluster_name) }
        end
        place_rps = place_rps.flatten.compact.select { |rp| is_suitable_resource_pool?(rp, mem) }
        vm_match_host_names = place_rps.map { |rp| rp.cluster.hosts.keys }.flatten.compact.uniq
      end

      def rp_id(rp)
        "#{rp.cluster.name}-#{rp.name}"
      end

      def init_self()
        return if @inited
        vm_groups.each_value do |vm_group|
          rpses = vm_group.req_rps.map do |cluster_name, rps|
            rps.map { |rp_name| clusters[cluster_name].resource_pools[rp_name] if clusters.key?(cluster_name) }
          end
          @rp_group[vm_group.name] = rpses.flatten.compact
        end
        existed_rp = {}
        @rp_group.each_value do |rplist|
          next if rplist.size <= 0
          logger.debug("rplist size: #{rplist.size}")
          (0...rplist.size).each do |n|
            logger.debug("rplist #{n}:#{rplist.first.pretty_inspect}")
            break if !existed_rp.key?(rp_id(rplist.first))
            rplist.rotate!
          end
          existed_rp[rp_id(rplist.first)] = 1
        end
        logger.debug("rp_groups:#{@rp_group.pretty_inspect}")
        @inited = true
      end

      def query_capacity(vmServers, info)
        init_self()
        hostnames = info["hosts"]
        match_host_names = nil
        total_memory = {}
        vmServers.each do |spec|
          group_name = spec['vm_group_name']
          vm_group = vm_groups[group_name]

          vm_match_host_names = suitable_host_with_rp(vm_group, spec['req_mem'])
          if match_host_names.nil?
            match_host_names = vm_match_host_names
          else
            match_host_names &= vm_match_host_names
          end
        end
        hostnames & match_host_names
      end

      def recommendation(vmServers, hostnames)
        init_self()
        rp_servers = {}
        hostnames.each do |hostname|
          mem_used = {}
          host_rp = []
          vmServers.each do |spec|
            group_name = spec['vm_group_name']
            rp_list = @rp_group[group_name].dup
            while !rp_list.empty?
              rp = rp_list.first
              mem_used[rp.name] = 0 if !mem_used.key?(rp.name)
              if rp.cluster.hosts.key?(hostname)
                if is_suitable_resource_pool?(rp, mem_used[rp.name].to_i + spec['req_mem'].to_i)
                  mem_used[rp.name] += spec['req_mem'].to_i
                  host_rp << RPServer.new(hosts[hostname], rp, spec['req_mem'], 1)
                  break
                end
                logger.debug("#{group_name} check next rp current: #{rp.name}")
                rp_list.sort { |x, y| x.used_counter <=> y.used_counter }
                next
              end
              logger.debug("#{group_name} rotate: #{rp.name}")
              rp_list.rotate!
            end
          end

          rp_servers[hostname] = host_rp
        end
        #index = 0
        #Hash[hostnames.map { |host| [host, vmServers.map { |vm| RPServer.new(hosts[host], nil, 100, index += 1) }] }]
        rp_servers
      end

      def commission(vmServers)
        vmServers.each do |vm|
          vm.rp.unaccounted_memory += vm.size
          vm.rp.used_counter += 1
        end
        true
      end

      def decommission(vmServers)
        vmServers.each do |vm|
          vm.rp.unaccounted_memory -= vm.size
          vm.rp.used_counter -= 1
        end
       end

    end

    class ResourcePool < CMService
      def initialize(cloud)
        super
        if config.enable_inner_rp_service
          @server = InnerRP.new(self)
        else
          # Init fog storage_server
          info = cloud.get_provider_info()
          @server = cloud.create_service_obj(config.storage_service, info) # Currently, we only use the first engine
        end
      end

      def name
        "resource_pool"
      end

      def create_servers(vm_specs)
        inner_create_servers(vm_specs) { config.enable_inner_rp_service }
      end

      def deploy(vmServer)
      end

      def delete(vmServer)
        @server.decommission(vmServer)
      end

    end

  end
end
