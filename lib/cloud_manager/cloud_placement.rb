module VHelper::CloudManager
  class VHelperCloud
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
    REMAIDER_DISK_SIZE = ResourceInfo::DISK_CHANGE_TIMES * 8
    HOST_SYS_DISK_SIZE = ResourceInfo::DISK_CHANGE_TIMES * 4

    def is_suitable_resource_pool?(rp, req_info)
      @logger.debug("limit:#{rp.limit_mem},real_free:#{rp.real_free_memory}, req:#{req_info.mem}")
      if rp.limit_mem != -1 && (rp.real_free_memory < req_info.mem)
        @logger.debug("No memory give to vm")
        return false
      end
      true
    end

    def datastore_group_match?(req_info, ds_name)
      @logger.debug("datastore pattern: #{req_info.disk_pattern.pretty_inspect}, name:#{ds_name}")
      req_info.disk_pattern.each {|d_pattern| return true unless d_pattern.match(ds_name).nil?}
      false
    end

    def get_suitable_sys_datastore(req_info, datastores)
      datastores.delete_if {|datastore| datastore.real_free_space < REMAIDER_DISK_SIZE }
      datastores.each { |datastore|
        #next if !datastore_group_match?(req_info, datastore.name)
        if datastore.real_free_space > REMAIDER_DISK_SIZE 
          datastore.unaccounted_space += HOST_SYS_DISK_SIZE
          return datastore
        end
      }
      nil
    end

    def get_suitable_datastores(datastores, req_info)
      req_size = req_info.disk_size
      datastores.delete_if {|datastore| datastore.real_free_space < REMAIDER_DISK_SIZE }
      used_datastores = []
      loop_resource(datastores) { |datastore|
#      datastores.each { |datastore|
        next if datastore.real_free_space < REMAIDER_DISK_SIZE
        next if !datastore_group_match?(req_info, datastore.name)
        free_size = datastore.real_free_space - REMAIDER_DISK_SIZE
        free_size = req_size if free_size > req_size 
        used_datastores << {:datastore => datastore, :size => free_size, :type => req_info.disk_type}
        req_size -= free_size.to_i
        break used_datastores if req_size.to_i <= 0 
      }
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

      used_datastores.each { |datastore|
        fullpath = "[#{datastore[:datastore].name}] #{vm.name}/data.vmdk" 
        @logger.debug("vm:#{datastore[:datastore].inspect}, used:#{datastore[:size].to_i}")
        datastore[:datastore].unaccounted_space += datastore[:size].to_i
        disk = vm.disk_add(datastore[:size].to_i, fullpath)
        disk.datastore_name = datastore[:datastore].name
        disk.type = datastore[:type]
      }
    end

    def hosts_prepare_in_cluster (cluster)
      hosts = cluster.hosts.values
      #hosts.shuffle!

      hosts.each { |host|
        next if host.place_share_datastores
        next if host.place_local_datastores
        host.place_share_datastores = host.share_datastores.values
        host.place_local_datastores = host.local_datastores.values
        host.place_share_datastores.shuffle!
        host.place_local_datastores.shuffle!
      }

      hosts
    end

    def set_vm_error_msg(vm, msg)
      vm.error_msg = "#{vm.error_msg}\n#{msg}"
      @logger.debug("ERROR: #{msg}")
    end

    def vm_group_placement(vm_group, group_place, hosts, cur_rp)
      vm_group.instances.times { |num|
        return 'next rp' unless is_suitable_resource_pool?(cur_rp, vm_group.req_info)
        vm_name = gen_vm_name(@cluster_name, vm_group.name, num)
        @logger.debug("vm_name: #{vm_name}")
        if (@existed_vms.has_key?(vm_name))
          @logger.debug("do not support change existed VM's setting")
          next
        end
        vm = VHelper::CloudManager::VmInfo.new(vm_name, @logger)
        vm.host_name = nil
        vm.status = VM_STATE_PLACE
        loop_resource(hosts) { |host|
          req_mem = vm_group.req_info.mem
          #@logger.debug("req mem #{req_mem}  ===> host :#{host.inspect}")
          if host.real_free_memory < req_mem
            set_vm_error_msg(vm, "#{host.name} haven't enough memory for #{vm_name} req:#{req_mem}, host has :#{host.real_free_memory}."\
              "And try to get next host.")
            next
          end
          #The host's memory is suitable for this VM

          #Get the sys_datastore for clone
          sys_datastore = get_suitable_sys_datastore(vm_group.req_info, host.place_share_datastores)

          if sys_datastore.nil?
            set_vm_error_msg(vm, "can not find suitable sys datastore in host #{host.name}. And try to find other host")
            next
          end
          @logger.debug("get sys datastore :#{sys_datastore.name}")

          #Get the datastore for this vm
          req_size = vm_group.req_info.disk_size
          place_datastores = host.place_share_datastores
          place_datastores = host.place_local_datastores if vm_group.req_info.disk_type == DISK_TYPE_LOCAL
          used_datastores = get_suitable_datastores(place_datastores, vm_group.req_info)
          if used_datastores.empty?
            #TODO no disk space for this vm
            set_vm_error_msg(vm, "No enough disk for #{vm_name}. req:#{req_size}. And try to find other host")
            next
          end
          #Find suitable Host and datastores
          host.place_share_datastores.rotate!
          @logger.debug("datastores: #{place_datastores.pretty_inspect}")
          assign_resources(vm, vm_group, cur_rp, sys_datastore, host, used_datastores)
          vm.error_msg = nil
          ## RR for next Host
          # Find a suitable place 
          group_place << vm
          #@logger.debug("Add #{vm.name} to preparing vms")
          @vm_lock.synchronize { @preparing_vms[vm.name] = vm }
          vm_group.add_vm(vm)
          break
        }
        if vm.error_msg
          #NO resource for this vm_group
          set_vm_error_msg(vm, "vm can not get resources in rp:#{cur_rp.name}. Try to look for other resource pool\n"\
                           "And the group:#{vm_group.name} has no resources to alloced rest #{vm_group.instances - num} vm")
          #Add failure vm to failure_vms que
          #@vm_lock.synchronize { @failure_vms[vm.name] = vm}
          return vm
        end
      }
      nil
    end

    #Select best placement order
    def set_best_placement_rp_list!(rp_list)
      rp_list.sort! {|x, y| x.used_counter <=> y.used_counter }
    end

    def cluster_placement(dc_resource, vm_groups_input, vm_groups_existed, cluster_info)
      vm_placement = []
      if vm_groups_existed.size > 0
        #TODO add changed placement logical
      end

      #Placement logical here
      vm_groups_input.each_value { |vm_group|
        #Check and find suitable resource_pool
        group_place = []
        need_next_rp = nil

        place_rp = []
        @logger.debug("req_rps:#{vm_group.req_rps}")
        vm_group.req_rps.each {|rp_name, cluster_name|
          place_rp << dc_resource.clusters[cluster_name].resource_pools[rp_name]
        }
        set_best_placement_rp_list!(place_rp)
        loop_resource(place_rp) { |rp|
          @logger.debug("Place rp:#{place_rp.pretty_inspect}")
          cluster = rp.cluster
          @logger.debug("used rp:#{rp.name} in cluster:#{cluster.name}")
          need_next_rp = nil
          hosts = hosts_prepare_in_cluster(cluster)
          need_next_rp = vm_group_placement(vm_group, group_place, hosts, rp)
          next if need_next_rp
          break
        }
        if need_next_rp
          ## can not alloc vm_group anymore
          vm = need_next_rp
          @cloud_error_msg_que << vm.error_msg
          group_failed = vm_group.instances - vm_group.vm_ids.size
          @placement_failed += group_failed
          @logger.debug("Can not place #{vm.name}, Try to place #{vm_group.vm_ids.size} / (#{vm_group.instances})")
          @logger.debug("VM group #{vm_group.name} failed to place #{group_failed} vm, total failed: #{@placement_failed}.")
        end
        vm_placement << group_place
      }

      vm_placement
    end

    def loop_resource(res)
      offset = 0
      res.each_with_index { |elem, idx| offset = idx + 1; yield elem }
    ensure
      res.rotate!(offset)
    end

  end
end
