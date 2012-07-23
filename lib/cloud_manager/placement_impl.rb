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

# @since serengeti 0.5.0
# @version 0.5.0
module Serengeti
  module CloudManager
    class FullPlacement < Placement
      def initialize(cloud)
        super(cloud)
        @logger = Serengeti::CloudManager::logger
      end

      # this method filter out existed VMs that violate instance_per_host constraint
      # TODO: should check group association constraints
      def pre_placement_cluster(vm_groups, existed_vms)
        @logger.debug("checking cluster status, filter out VMs that violate instancePerHost constraint")
        vm_groups = vm_groups.values
        target_vg = vm_groups.select { |vm_group| vm_group.instance_per_host }
        return nil if target_vg.size == 0

        target_vg_names = target_vg.map { |vm_group| vm_group.name }

        vm_distribution = {}
        existed_vms.each do |name, vm_info|
          if target_vg_names.include? vm_info.group_name
            vm_distribution[vm_info.group_name] ||= {}
            vm_distribution[vm_info.group_name][vm_info.host_name] ||= []
            vm_distribution[vm_info.group_name][vm_info.host_name] << vm_info
          end
        end

        delete_vms = []
        vm_distribution.each do |vg_name, host_usages|
          vg = vm_groups.find { |vg| vg.name == vg_name}
          host_usages.each do |host, vms|
           # delete vms that violate instance_per_host constraint
            if vms.size != vg.instance_per_host
              delete_vms.concat(vms)
              vms.each do |vm|
                @logger.debug("remove VM " + vm.name + " on host " + host + \
                    " as it violates instance_per_host constraint.")
              end
              next
            end
            # delete vms that violate STRICT group association constraint
            if vg.referred_group and vg.associate_type == 'STRICT' and \
                (vm_distribution[vg.referred_group].nil? or not vm_distribution[vg.referred_group].key?(host))
              delete_vms.concat(vms)
              vms.each do |vm|
                @logger.debug("remove VM " + vm.name + " on host " + host + \
                    " as it violates STIRCT group association constraint.")
              end
            end
          end
        end

        [ {'act'=>'group_delete', 'group' => delete_vms} ]
      end

      # this method should only be called once, during a placement cycle
      # initialize the object. FIXME put into initialize 
      def get_virtual_groups(vm_groups)
        # Don't combine any associated groups for now
        # TODO: use the concept of virtual_groups
        @vm_groups = {}

        # sort the groups to put referred groups in front
        vm_groups.each do |name, group_info|
          if group_info.referred_group
            if @vm_groups.key?(group_info.referred_group)
              @vm_groups[name] = group_info
            else
              # Assert the referred group exists
              @vm_groups[group_info.referred_group] = vm_groups[group_info.referred_group]
              @vm_groups[name] = group_info
            end
          else
            @vm_groups[name] = group_info
          end
        end

        # host map by cluster {:host1 => 5, :host2 => 1}
        @host_map_by_cluster = {}

        # host map by group, {:group1 => {:host1 => 2, :host2 => 4}, ...}
        @host_map_by_group = {}
        @vm_groups.each {|name, _| @host_map_by_group[name] = {}}
        
        @vm_groups
      end

#      def gen_cluster_vm_name(group_name, num)
#        "vm" + num.to_s
#      end

      def increase_host_usage(group_name, host_name, vm_cnt)
        if @host_map_by_cluster.key?(host_name)
          @host_map_by_cluster[host_name] += vm_cnt
        else
          @host_map_by_cluster[host_name] = vm_cnt
        end

        if @host_map_by_group[group_name].key?(host_name)
          @host_map_by_group[group_name][host_name] += vm_cnt
        else
          @host_map_by_group[group_name][host_name] = vm_cnt
        end
      end

      def least_used_host(candidates)
        least_cnt = nil
        candidate = nil
        candidates.each do |host, _|
          # this host is never used before, return
          return host unless @host_map_by_cluster.key?(host)

          if least_cnt.nil?
            least_cnt = @host_map_by_cluster[host]
            candidate = host
          elsif @host_map_by_cluster[host] < least_cnt
            least_cnt = @host_map_by_cluster[host]
            candidate = host
          end
        end
        candidate
      end
      
      # Virtual node is a group of VM that should be placed on the same host
      # call this method for each virtual group once
      def get_virtual_nodes(virtual_group, existed_vms, placed_vms)
        # explicitly spell out a virtual_group is a vm_group
        vm_group = virtual_group
        virtual_nodes = []
        cnt = 0
        vnode = VirtualNode.new
        (0...vm_group.instances).each do |num|
          vm_name = gen_cluster_vm_name(vm_group.name, num)
          if existed_vms.key?(vm_name)
            host_name = existed_vms[vm_name].host_name
            @logger.debug("found existed VM " + vm_name + " in group " + \
                vm_group.name + " on host " + host_name)
            increase_host_usage(vm_group.name, host_name, 1)
            # skip existed VM
            next
          end

          cnt += 1
          vnode.add(VmSpec.new(vm_group, vm_name))
          if vm_group.instance_per_host
            next if cnt % vm_group.instance_per_host != 0
          end

          virtual_nodes << vnode
          @logger.debug("Virtual node include vms " + vnode.to_s)
          vnode = VirtualNode.new
        end
        
        validate_host_map(vm_group.name, vm_group.instance_per_host) if vm_group.instance_per_host        
        virtual_nodes
      end

      # validate the instance_per_host constraint for vm group
      def validate_host_map(vm_group, instance_per_host)
        @logger.debug("check the instance_per_host constraint on vm group " + vm_group)
        @host_map_by_group[vm_group].each do |host, vm_cnt|
          if not vm_cnt.nil? and vm_cnt != instance_per_host
            @logger.error("vm group " + vm_group + " on host " + host + \
                " has " + vm_cnt.to_s + " vms. It violates [instance_per_host=" + \
                instance_per_host.to_s + "] constraint")
            raise Serengeti::CloudManager::PlacementException, "vm_group " + vm_group + \
              " violates [instance_per_host=" + instance_per_host.to_s + "] constraint"
          end
        end
      end
      
      # Assumptions:
      # 1. referred groups should be placed before the groups that have group associations
      # 2. host availability organize in format {"stroage" => {host2 => val1, host1 => val2,..}, ...}
      #    hosts are organized in the order from high priority to low priority
      # 3. only consider the storage resource right now
      def select_host(virtual_node, resource_availability)
        @logger.debug("select host for virtual node " + virtual_node.to_s + \
            " with host availability " + resource_availability.to_s)

        if virtual_node.vm_specs.size == 0
          raise Serengeti::CloudManager::PlacementException, \
            "Internal error: virtual node should contain at least one vm"
        end

        candidates = resource_availability['storage']
        if candidates.empty?
          @logger.error("input available host list cannot be empty")
          raise Serengeti::CloudManager::PlacementException, \
            "input available host list cannot be empty"
        end

        # right now all nodes in virtual_node belongs to a single vm_group
        vm_group = @vm_groups[virtual_node.vm_specs[0].group_name]
        host_map = @host_map_by_group[vm_group.name]

        # remove hosts that have VM placed so that to satisfy instance_per_host requirement
        if vm_group.instance_per_host
          validate_host_map(vm_group.name, vm_group.instance_per_host)
          candidates = candidates.select {|host, _| not host_map.key?(host)}
          @logger.debug("hosts " + candidates.keys.to_s + \
              " left after instance_per_host constraint checking")
          if candidates.empty?
            @logger.error("available host list is empty after \
              instance_per_host constraint check")
            raise Serengeti::CloudManager::PlacementException, \
              "available host list is empty after checking instance_per_host constraint"
          end
        end
        
        if vm_group.referred_group
          # this group associate with another vm group
          referred_group_host_map = @host_map_by_group[vm_group.referred_group]

          if referred_group_host_map.empty?
            @logger.error("failed to place virtual node in group " + \
                vm_group.name + ". Referenced group " + \
                vm_group.referred_group + " should be placed first" )
            raise Serengeti::CloudManager::PlacementException, \
              "referenced vm_group " + vm_group.referred_group + " should be placed first"
          end

          referred_candidates = candidates.select {|host, _| referred_group_host_map.key?(host)}
          not_referred_candidates = candidates.select {|host, _| not referred_group_host_map.key?(host)}

          if vm_group.associate_type == 'STRICT' and referred_candidates.empty?
            @logger.error("unable to satisfy STRICT assocaition with group " + \
                vm_group.referred_group + ". Hosts from referred group are all not available")
            raise Serengeti::CloudManager::PlacementException, \
              "host outage, unable to satisfy STIRCT association with group " \
              + vm_group.referred_group
          end

          candidate = least_used_host(referred_candidates)
          candidate = least_used_host(not_referred_candidates) if candidate.nil?
          
          candidate
        else
          # no group association, return the least used candidate
          least_used_host(candidates)
        end
      end

      def assign_host(virtual_node, host_name)
        @logger.debug("assign host " + host_name + " to virtual_node " + virtual_node.to_s)

        # right now all nodes in virtual_node belongs to a single vm_group
        vm_group = @vm_groups[virtual_node.vm_specs[0].group_name]
        validate_host_map(vm_group.name, vm_group.instance_per_host) if vm_group.instance_per_host

        if vm_group.instance_per_host.nil?
          vm_cnt = 1
        else
          vm_cnt = vm_group.instance_per_host
        end

        increase_host_usage(vm_group.name, host_name, vm_cnt)        
      end
    end
  end
end
