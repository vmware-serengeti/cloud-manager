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
    class Cloud
      VM_PLACE_SWAP_DISK  = true
      VM_SYS_DISK_COLOCATED_WITH_DATA_DISK = true
      VM_DATA_DISK_START_INDEX = (VM_PLACE_SWAP_DISK) ? 2 : 1
      SWAP_MEM_SIZE = [2048, 4096, 16384, 65536]
      SWAP_DISK_SIZE = [1024, 2048, 4096, 8192]
      MAX_SWAP_DISK_SIZE = 12288
      # refine work: TODO
      # 1. change placement result to a hash structure
      # 2. abstract placement function to a base class
      # 3. put all place-related functions to one class
      # 4. extend RR class from base class
      ##########################################################
      # template placement
      def gem_template_name(template_name, datastore)
        return "#{template_name}-#{datastore.mob}"
      end

      def template_place(dc_resources, vm_groups_existed, vm_groups_input, placement)
        t_place = []
        # TODO check template vm
        temp_hash = {}

        # TODO calc template should clone to which hosts/datastores

        t_place
      end

      ############################################################
      # Only RR for rps/hosts/datastores selected
      REMAINDER_DISK_SIZE = 16 * 1024 #MB
      MIN_DISK_SIZE = 1 * 1024 #MB
      VM_SYS_DISK_SIZE = 5 * 1024 #MB

      def is_suitable_resource_pool?(rp, req_info)
        @logger.debug("limit:#{rp.limit_mem}, real_free:#{rp.real_free_memory}, req:#{req_info.mem}")
        if rp.limit_mem != -1 && (rp.real_free_memory < req_info.mem)
          @logger.debug("rp:#{rp.name} has not enough memory to vm_group")
          return false
        end
        true
      end

      def datastore_group_match?(disk_pattern, ds_name)
        @logger.debug("datastore pattern: #{disk_pattern.pretty_inspect}, name:#{ds_name}")
        disk_pattern.each { |d_pattern| return true unless d_pattern.match(ds_name).nil? }
        false
      end

      def vm_sys_disk_size
        return @vm_sys_disk_size if @vm_sys_disk_size
        VM_SYS_DISK_SIZE
      end

      def get_suitable_sys_datastore(datastores)
        datastores.delete_if { |datastore| datastore.real_free_space < REMAINDER_DISK_SIZE }
        datastores.each do |datastore|
          #next if !datastore_group_match?(req_info, datastore.name)
          return datastore if datastore.real_free_space > REMAINDER_DISK_SIZE
        end
        nil
      end

      def get_suitable_datastores(datastores, disk_pattern, req_size, disk_type, can_split)
        datastores.delete_if { |datastore| datastore.real_free_space <= REMAINDER_DISK_SIZE }
        used_datastores = []
        loop_resource(datastores) do |datastore|
          next 'remove' if datastore.real_free_space.to_i <= REMAINDER_DISK_SIZE
          next 'remove' if !datastore_group_match?(disk_pattern, datastore.name)
          free_size = datastore.real_free_space.to_i - REMAINDER_DISK_SIZE
          next 'skip' if free_size < MIN_DISK_SIZE
          @logger.debug("free size :#{free_size}MB, req size:#{req_size}MB")
          if free_size > req_size
            free_size = req_size
          else
            if !can_split
              @logger.debug("in datastore:#{datastore.name} can not split to different disks, req size:#{req_size}MB")
              next 'skip'
            end
          end
          used_datastores << { :datastore => datastore, :size => free_size, :type => disk_type }
          req_size -= free_size.to_i
          break if req_size.to_i <= 0
        end
        used_datastores
      end

      def assign_resources(vm, vm_group, cur_rp, sys_datastore, host, used_datastores)
        req_mem = vm_group.req_info.mem
        cur_rp.unaccounted_memory += req_mem
        host.unaccounted_memory += req_mem

        vm.host_name  = host.name
        vm.host_mob   = host.mob
        vm.req_rp     = vm_group.req_info

        vm.sys_datastore_moid = sys_datastore.mob
        vm.resource_pool_moid = cur_rp.mob
        vm.template_id = vm_group.req_info.template_id
        vm.rp_name = cur_rp.name
        vm.rp_cluster_name = cur_rp.cluster.name
        vm.vm_group = vm_group
        vm.network_res = vm_group.network_res
        vm.ha_enable = vm_group.req_info.ha
        cur_rp.used_counter += 1

        sys_datastore.unaccounted_space += vm_sys_disk_size
        disk = vm.disk_add(vm_sys_disk_size, 'system disk')
        disk.datastore_name = sys_datastore.name
        disk.type = 'system'
        unit_number = 0
        disk.unit_number = unit_number
        used_datastores.each do |datastore|
          fullpath = "[#{datastore[:datastore].name}] #{vm.name}/#{datastore[:type]}#{unit_number}.vmdk"
          @logger.debug("vm:#{datastore[:datastore].inspect}, used:#{datastore[:size].to_i}MB")
          datastore[:datastore].unaccounted_space += datastore[:size].to_i
          disk = vm.disk_add(datastore[:size].to_i, fullpath)
          disk.datastore_name = datastore[:datastore].name
          disk.shared = (vm_group.req_info.disk_type == DISK_TYPE_SHARE)
          unit_number += 1
          disk.unit_number = unit_number
          disk.type = datastore[:type]
        end

      end

      def hosts_prepare_in_cluster (cluster)
        hosts = cluster.hosts.values
        #hosts.shuffle!

        hosts.each do |host|
          next if host.place_share_datastores
          next if host.place_local_datastores
          host.place_share_datastores = host.share_datastores.values
          host.place_local_datastores = host.local_datastores.values
          host.place_share_datastores.shuffle!
          host.place_local_datastores.shuffle!
        end

        hosts
      end

      def set_vm_error_msg(vm, msg)
        vm.error_msg = "#{msg}"
        @logger.warn("#{msg}")
      end

      def vm_group_placement(vm_group, group_place, existed_vms, hosts, cur_rp)
        (vm_group.size...vm_group.instances).each do |num|
          return "rp:#{cur_rp.name} has not enough memory to vm_group #{vm_group.name}" \
              if !is_suitable_resource_pool?(cur_rp, vm_group.req_info)

          vm_name = gen_cluster_vm_name(vm_group.name, num)
          if existed_vms.key?(vm_name)
            @logger.debug("do not support change existed VM's setting")
            existed_vms[vm_name].action = VM_ACTION_START
            next
          end
          if @placed_vms.key?(vm_name)
            @logger.debug("do not change prepared VM's setting")
            next
          end
          vm = Serengeti::CloudManager::VmInfo.new(vm_name)
          vm.host_name = nil
          vm.status = VM_STATE_PLACE
          loop_resource(hosts) do |host|
            req_mem = vm_group.req_info.mem
            # Add memory overcommmitment later
            if host.real_free_memory < req_mem
              set_vm_error_msg(vm, "#{host.name} doesn't have enough memory for #{vm_name}"\
                               "(#{req_mem}MB required), it only has #{host.real_free_memory}MB avaiable.")
              next 'remove'
            end
            #The host's memory is suitable for this VM

            #Place Disks system/swap/data disks
            #FIXME add roll back operations later
            place_datastores_used = (vm_group.req_info.disk_type == DISK_TYPE_LOCAL) ? \
              host.place_local_datastores : host.place_share_datastores
            sys_datastore = []

            #Get the sys_datastore for clone
            if VM_SYS_DISK_COLOCATED_WITH_DATA_DISK
              sys_datastore = get_suitable_sys_datastore(place_datastores_used)
            else
              sys_datastore = get_suitable_sys_datastore(host.place_share_datastores)
            end

            if sys_datastore.nil?
              set_vm_error_msg(vm, "Can not find enough disk space for creating vm #{vm.name} in host #{host.name}.")
              next 'remove'
            end
            @logger.debug("vm:#{vm.name} get sys datastore :#{sys_datastore.name}")

            used_datastores = []
            swap_datastores = []
            #Get the swap for this vm
            if VM_PLACE_SWAP_DISK
              swap_size = SWAP_MEM_SIZE.each_index { |i| break SWAP_DISK_SIZE[i] if req_mem < SWAP_MEM_SIZE[i] }
              swap_size = MAX_SWAP_DISK_SIZE if swap_size.nil?
              swap_datastores = get_suitable_datastores(place_datastores_used,
                                    vm_group.req_info.disk_pattern, swap_size,
                                    'swap', false)
              @logger.debug("Place swap #{swap_size}MB in #{swap_datastores.pretty_inspect}")
              if swap_datastores.empty?
                set_vm_error_msg(vm, "No enough disk space for #{vm_name}'s swap disk (#{swap_size}MB required).")
                next 'remove'
              end
            end
            #Get the datastore for this vm
            req_size = vm_group.req_info.disk_size

            data_datastores = get_suitable_datastores(place_datastores_used,
                                    vm_group.req_info.disk_pattern, req_size,
                                    'data', true)
            if data_datastores.empty?
              set_vm_error_msg(vm, "No enough disk space for #{vm_name}'s data disk (#{req_size}MB required).")
              next 'remove'
            end

            #Get the network for this vm
            vm.network_config_json = vm_group.network_res.card_num.times.collect \
              { |card| vm_group.network_res.get_vm_network_json(card) }

            host.place_share_datastores.rotate!

            used_datastores = swap_datastores + data_datastores
            @logger.debug("vm:#{vm.name} uses datastores: #{used_datastores.pretty_inspect}")

            # Assign resource 
            assign_resources(vm, vm_group, cur_rp, sys_datastore, host, used_datastores)
            vm.action = VM_ACTION_CREATE
            vm.error_msg = nil
            # RR for next Host
            # Find a suitable place
            group_place << vm
            @logger.debug("Add #{vm.name} to preparing queue")
            @vm_lock.synchronize { @placed_vms[vm.name] = vm }
            vm_group.add_vm(vm)
            break
          end

          return vm.error_msg if vm.error_msg #NO resource for this vm_group
        end
        nil
      end

      #Select best placement order
      def set_best_placement_rp_list(rp_list)
        rp_list.sort { |x, y| x.used_counter <=> y.used_counter }
      end

      # place cluster into cloud server
      def cluster_placement(dc_resource, vm_groups_input, vm_groups_existed, cluster_info)
        vm_placement = []
        if vm_groups_existed.size > 0
          #TODO add changed placement logical
        end

        @dc_template_vm = dc_resource.vm_template
        #Placement logical here
        vm_groups_input.each_value do |vm_group|
          #Check port group for vm_group
          unknown_pg = vm_group.network_res.not_existed_port_group(dc_resource.port_group)
          if unknown_pg
            failed_vms = vm_group.instances - vm_group.vm_ids.size
            error_msg = "group #{vm_group.name}: can not find port group:#{unknown_pg} in vSphere."
            @logger.error(error_msg)
            @placement_failed += failed_vms
            @cloud_error_msg_que << error_msg
            break
          end

          group_place = []
          place_err_msg = nil

          #Check and find suitable resource_pool
          @logger.debug("Group:#{vm_group.name} req_rps:#{vm_group.req_rps}")

          # prepareing rp for this vm_group
          place_rp = vm_group.req_rps.map do |cluster_name, rps|
            rps.map { |rp_name| dc_resource.clusters[cluster_name].resource_pools[rp_name] if dc_resource.clusters[cluster_name]}
          end
          place_rp = set_best_placement_rp_list(place_rp.flatten.compact)
          if place_rp.nil? || place_rp.size == 0
            failed_vms = vm_group.instances - vm_group.vm_ids.size
            @placement_failed += failed_vms
            err_msg = "Can not get any resource pools for vm group #{vm_group.name}. failed to place #{failed_vms} VM"
            @logger.error(err_msg)
            @cloud_error_msg_que << err_msg
            next
          end

          loop_resource(place_rp) do |rp|
            #@logger.debug("Place rp:#{place_rp.pretty_inspect}")
            cluster = rp.cluster
            @logger.debug("used rp:#{rp.name} in cluster:#{cluster.name}")
            place_err_msg = nil
            hosts = hosts_prepare_in_cluster(cluster)

            place_err_msg = vm_group_placement(vm_group, group_place, @existed_vms, hosts, rp)
            next 'remove' if place_err_msg
            break
          end
          if place_err_msg
            ## can not alloc vm_group anymore
            @cloud_error_msg_que << "Can not alloc resource for vm group #{vm_group.name}: #{place_err_msg}"
            failed_vms = vm_group.instances - vm_group.vm_ids.size
            @placement_failed += failed_vms
            @logger.error("VM group #{vm_group.name} failed to place #{failed_vms} vm, total failed: #{@placement_failed}.")
          end
          vm_placement << group_place
        end

        vm_placement
      end

      def loop_resource(res)
        while !res.empty?
          res.shift if ((yield res.first) == 'remove')
          res.rotate!
        end
      ensure
        res.rotate! unless res.empty?
      end

    end
  end
end
