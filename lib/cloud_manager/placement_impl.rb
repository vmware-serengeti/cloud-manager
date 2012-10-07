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

# @version 0.5.0
module Serengeti
  module CloudManager
    class FullPlacement < Placement
      def initialize(cloud)
        super(cloud)
      end

      # this method filter out existed VMs that violate instance_per_host constraint
      # TODO: should check group association constraints
      def pre_placement_cluster(vm_groups, existed_vms)
        result = super
        return result if !result.nil?
        @host_map_by_group = {}

        logger.debug("checking cluster status, filter out VMs that violate instancePerHost constraint")
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
          @host_map_by_group[vm_info.group_name] ||= {}
          @host_map_by_group[vm_info.group_name][vm_info.host_name] ||= 0
          @host_map_by_group[vm_info.group_name][vm_info.host_name] += 1
        end

        delete_vms = []
        vm_distribution.each do |vg_name, host_usages|
          vg = vm_groups.find { |vg| vg.name == vg_name}
          host_usages.each do |host, vms|
           # delete vms that violate instance_per_host constraint
            if vms.size != vg.instance_per_host
              delete_vms.concat(vms)
              vms.each do |vm|
                logger.debug("remove VM " + vm.name + " on host " + host + \
                    " as it violates instance_per_host constraint.")
              end
              next
            end
            # delete vms that violate STRICT group association constraint
            if vg.referred_group and vg.is_strict? and \
                (vm_distribution[vg.referred_group].nil? or not vm_distribution[vg.referred_group].key?(host))
              delete_vms.concat(vms)
              vms.each do |vm|
                logger.debug("remove VM " + vm.name + " on host " + host + \
                    " as it violates STIRCT group association constraint.")
              end
            end
          end
        end

        return nil if delete_vms.empty?

        {:action => [ {'act'=>'group_delete', 'group' => delete_vms} ],
         :rollback => 'fetch_info'}
      end

      # this method should only be called once, during a placement cycle
      def get_virtual_groups(vm_groups)
        @input_vm_groups = vm_groups

        leaf_groups = []
        virtual_groups = {}
        strict_group = {}
        vm_groups.each do |name, group_info|
          logger.debug("group:#{name}, ref:#{group_info.referred_group}")
          #logger.debug("group info:#{group_info.pretty_inspect}")
          if group_info.referred_group
            refer_group = vm_groups[group_info.referred_group]
            raise "Unknown referred group name:#{group_info.referred_group}." if refer_group.nil?
            if refer_group.instance_per_host
              if group_info.is_strict? and group_info.instance_per_host
                strict_group[group_info.referred_group] ||= []
                strict_group[group_info.referred_group].push(group_info)
              else
                leaf_groups.unshift(name)
                leaf_groups.unshift(group_info.referred_group)
              end
            else
              leaf_groups.push(name)
            end
          else
            leaf_groups.push(name)
          end
          @host_map_by_group[name] ||= {}
        end
        leaf_groups.uniq!

        strict_group.each do |name, groups|
          #logger.debug("leaf_group:#{leaf_groups.pretty_inspect} has #{name}? #{leaf_groups.include?(name)}")
          if !leaf_groups.include?(name)
            raise Serengeti::CloudManager::PlacementException, "Referred group do not existed"\
              "and we do not support nested referred group #{name}."
          end

          virtual_groups["#{name}-related"] = VirtualGroup.new(vm_groups[name])
          virtual_groups["#{name}-related"].concat(groups)
          leaf_groups.delete(name)
        end

        leaf_groups.each { |name| virtual_groups[name] = VirtualGroup.new(vm_groups[name]) }

        if !config.cloud_hosts_to_rack.empty?
          # Init rack info
          @vm_racks = config.cloud_rack_to_hosts.keys
        end
        logger.debug("virtual_groups:#{virtual_groups.inspect}")
        virtual_groups
      end

      def rack_used_candidates(candidates, virtual_node)
        return candidates if config.cloud_rack_to_hosts.empty?
        #Add rack checking
        rack_type = nil
        racks = nil
        groups = {}
        referred_group = {}
        virtual_node.each do |vm|
          group = @input_vm_groups[vm.spec['vm_group_name']]
          next if group.nil?
          logger.debug("rack group:#{group.name}")
          logger.debug("rack group policy:#{group.rack_policy.pretty_inspect}")
          if group.referred_group
            logger.debug("rack referred_group:#{group.referred_group}")
            referred_group[group.referred_group] ||= 0 
            referred_group[group.referred_group] += 1
            raise Serengeti::CloudManager::PlacementException,\
              "Do not support more than one referred group in rack policy." if referred_group.size > 1
            ref_group_name = referred_group.keys[0]
            ref_group = @input_vm_groups[ref_group_name]
            raise Serengeti::CloudManager::PlacementException,\
              "\"#{ref_group_name}\" group does not existed." if ref_group.nil?
            if group.is_strict?
              logger.debug("strict group, use 'ref_group' rack info")
              rack_type = ref_group.rack_policy.type
              racks = ref_group.rack_policy.racks
              break
            end
          end
          groups[group.name] = 1
          next if group.rack_policy.nil?

          rack_type ||= group.rack_policy.type
          if rack_type != group.rack_policy.type
            rack_type = VmGroupRack::SAMERACK
          end
          logger.debug("rack_policy:#{group.rack_policy.pretty_inspect}")
          racks ||= group.rack_policy.racks
          racks &= group.rack_policy.racks if !group.rack_policy.racks.nil?
        end

        logger.debug("type:#{rack_type.to_s}, racks:#{racks.pretty_inspect}")
        return candidates if rack_type.nil?
        raise Serengeti::CloudManager::PlacementException,\
          "Can not find suitable rack with #{groups.keys.pretty_inspect}." if racks.empty?
 
        if rack_type == VmGroupRack::SAMERACK
          logger.debug("Create host with SAMERACK:#{racks.pretty_inspect}, candidate:#{candidates.keys.pretty_inspect}")
          hosts = config.cloud_rack_to_hosts[racks[0]]
          rack_candidates = candidates.keys & hosts
          logger.debug("rack hosts :#{hosts.pretty_inspect}")
          return candidates.select { |host, _| rack_candidates.include?(host)}  if !rack_candidates.empty?
        else
          # rack type is ROUNDROBIN
          logger.debug("ROUDROBIN rack:#{racks.pretty_inspect}, all rack:#{@vm_racks.pretty_inspect}")
          candidate = rr_items(racks, @vm_racks) do |rack|
            logger.debug("checking rack :#{rack}, c:#{candidates.keys}, config:#{config.cloud_rack_to_hosts[rack]}")
            rack_candidates = candidates.keys & config.cloud_rack_to_hosts[rack]
            return candidates.select { |host, _| rack_candidates.include?(host)} if !rack_candidates.empty?
          end
        end
        nil
      end

      def rr_items(candidates, all_items)
        moved = []
        result = nil
        begin
          all_items.each do |candidate|
            next if !candidates.include?(candidate)
            moved.push(candidate)
            yield candidate
          end
        ensure
          all_items.delete_if {|i| moved.include?(i)}
          moved.each { |i| all_items.push(i) }
        end
      end

      def add_vm_to_vnode(vnode, group, existed_vms)
        return if group.created_num >= group.instances
        vm_name = gen_cluster_vm_name(group.name, group.created_num)
        #logger.debug("create vm:#{vm_name}")
        group.created_num += 1
        return if existed_vms.key?(vm_name)
        #logger.debug("vm:#{vm_name} do not existed, need create")
        vnode.add(VmSpec.new(group, vm_name))
      end

      def create_vn_with_group(groups, existed_vms)
        vnode = VirtualNode.new
        yield vnode
        groups.each do |group|
          group.created_num ||= 0
          instances = group.instance_per_host || 1
          (0...instances).each { |_| add_vm_to_vnode(vnode, group, existed_vms) }
        end
        vnode
      end

      def create_vns_with_group(group, existed_vms)
        virtual_nodes = [] 
        (0...group.instances).each do |_|
          vnode = create_vn_with_group([group], existed_vms) { |_| }
          logger.debug("[#{group.created_num}, #{group.instances}] #{group.name}")
          virtual_nodes << vnode if !vnode.empty?
        end
        virtual_nodes 
      end

      # Virtual node is a group of VM that should be placed on the same host
      # call this method for each virtual group once
      def get_virtual_nodes(virtual_group, existed_vms, placed_vms)
        virtual_nodes = []
        if virtual_group.size > 1
          master_group = virtual_group.shift
          master_group.created_num ||= 0

          (0...master_group.instances).each do |num|
            vnode = create_vn_with_group(virtual_group, existed_vms) do |vnode|
              logger.debug("master [#{master_group.created_num}, #{master_group.instances}] ")
              break nil if master_group.created_num >= master_group.instances
              (0...master_group.instance_per_host).each {|_| add_vm_to_vnode(vnode, master_group, existed_vms) }
            end
            #logger.debug("vnode:#{vnode.pretty_inspect}")
            virtual_nodes << vnode if !vnode.nil? and !vnode.empty?
          end
        else
          virtual_nodes.concat(create_vns_with_group(virtual_group.first, existed_vms))
        end
        virtual_nodes
      end

      # Assumptions:
      # 1. referred groups should be placed before the groups that have group associations
      # 2. host availability organize in format {"stroage" => {host2 => val1, host1 => val2,..}, ...}
      #    hosts are organized in the order from high priority to low priority
      # 3. only consider the storage resource right now
      def select_host(virtual_node, resource_availability, all_hosts)
        #logger.debug("select host for virtual node " + virtual_node.to_s + \
        #    " with host availability " + resource_availability.to_s)

        if virtual_node.vm_specs.size == 0
          raise Serengeti::CloudManager::PlacementException, \
            "Internal error: virtual node should contain at least one vm."
        end

        candidates = resource_availability['storage']
        if candidates.empty?
          logger.error("Input available host list cannot be empty")
          raise Serengeti::CloudManager::PlacementException, \
            "Input available host list cannot be empty."
        end

        candidates_list = []

        groups = {}
        virtual_node.each { |spec| groups[spec.group_name] = 1 }

        # remove hosts that have VM placed so that to satisfy strict requirement
        virtual_node.each do |spec|
          group = @input_vm_groups[spec.group_name]
          if group.instance_per_host
            candidates = candidates.select do |host, _|
              @host_map_by_group[group.name][host].to_i < group.instance_per_host
            end
            logger.debug("#{spec.name} group: #{group.name} after instance_per_host checking: #{candidates.keys}")
          end
          candidates_list.push(candidates)

          next if groups.size > 1

          referred_group_name = group.referred_group
          next if referred_group_name.nil?

          associated_candidates = candidates.select do |host, _|
            logger.debug("#{referred_group_name}, #{host} no.#{@host_map_by_group[referred_group_name][host].to_i}")
            @host_map_by_group[referred_group_name][host].to_i > 0
          end
          logger.debug("vm name:#{spec.name} hosts " + associated_candidates.keys.to_s + \
                       " left after strict constraint checking")
          if associated_candidates.nil?
            next if !group.is_strict?
            err_msg = "Available host list is empty after checking strict constraint."
            logger.error(err_msg)
            raise Serengeti::CloudManager::PlacementException, err_msg
          end
          candidates_list.unshift(associated_candidates)
        end

        candidates_list.each do |cand|
          c = rack_used_candidates(cand, virtual_node)
          next if c.nil?
          logger.debug("rack used return :#{c.keys.pretty_inspect}")
          rr_items(c.keys, all_hosts) { |host| return host }
        end
        nil
      end

      def assign_host(virtual_node, host_name)
        virtual_node.each do |spec|
          logger.debug("#{spec.name} assign host #{host_name} to virtual_node #{virtual_node.inspect}")
          @host_map_by_group[spec.group_name][host_name] ||= 0
          @host_map_by_group[spec.group_name][host_name] += 1
        end
      end
    end
  end
end
