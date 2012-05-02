module VHelper::CloudManager
  class VHelperCloud
    ############################################################
    # Only RR for rps/hosts/datastores selected
    REMAIDER_DISK_SIZE = ResourceInfo::DISK_CHANGE_TIMES * 20
    HOST_SYS_DISK_SIZE = ResourceInfo::DISK_CHANGE_TIMES * 16

    def is_suitable_resource_pool?(rp, req_info)
      @logger.debug("limit:#{rp.limit_mem},real_free:#{rp.real_free_memory}, req:#{req_info.mem}")
      if rp.limit_mem != -1 && (rp.real_free_memory < req_info.mem)
        @logger.debug("No memory give to vm")
        return false
      end
      true
    end

    def get_suitable_sys_datastore(datastores)
      datastores.delete_if {|datastore| datastore.real_free_space < REMAIDER_DISK_SIZE }
      datastores.each { |datastore|
        if datastore.real_free_space > REMAIDER_DISK_SIZE 
          datastore.unaccounted_space += HOST_SYS_DISK_SIZE
          return datastore
        end
      }
      nil
    end

    def get_suitable_datastores(datastores, req_size)
      datastores.delete_if {|datastore| datastore.real_free_space < REMAIDER_DISK_SIZE }
      used_datastores = []
      datastores.each do |datastore|
        next if datastore.real_free_space < REMAIDER_DISK_SIZE
        free_size = datastore.real_free_space - REMAIDER_DISK_SIZE
        free_size = req_size if free_size > req_size 
        used_datastores << {:datastore => datastore, :size=>free_size}
        req_size -= free_size.to_i
        return used_datastores if req_size.to_i <=0 
      end
      []
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
      cur_rp.used_counter += 1

      used_datastores.each { |datastore|
        fullpath = "[#{datastore[:datastore].name}] #{vm.name}/data.vmdk" 
        datastore[:datastore].unaccounted_space += datastore[:size].to_i
        disk = vm.disk_add(datastore[:size].to_i, fullpath)
        disk.datastore_name = datastore[:datastore].name
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
      vm.error_msg = msg
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
        hosts.rotate!
        loop_resource(hosts) { |host|
          req_mem = vm_group.req_info.mem
          #@logger.debug("req mem #{req_mem}  ===> host :#{host.inspect}")
          if host.real_free_memory < req_mem
            vm.error_msg = "#{host.name} haven't enough memory for #{vm_name} req:#{req_mem}, host has :#{host.real_free_memory}."
            @logger.debug(vm.error_msg)
            next
          end
          #The host's memory is suitable for this VM
          host.place_share_datastores.rotate!

          #Get the sys_datastore for clone
          sys_datastore = get_suitable_sys_datastore(host.place_share_datastores)

          if sys_datastore.nil?
            set_vm_error_msg(vm, "can not find suitable sys datastore in host #{host.name}.")
            next
          end
          @logger.debug("get sys datastore :#{sys_datastore.name}")

          #Get the datastore for this vm
          req_size = vm_group.req_info.disk_size
          used_datastores = get_suitable_datastores(host.place_share_datastores, req_size)
          if used_datastores.empty?
            #TODO no disk space for this vm
            set_vm_error_msg(vm, "No enough disk for #{vm_name}.")
            next
          end
          #Find suitable Host and datastores
          assign_resources(vm, vm_group, cur_rp, sys_datastore, host, used_datastores)
          vm.error_msg = nil
          ## RR for next Host
          break
        }
        if vm.error_msg
          #NO resource for this vm_group
          set_vm_error_msg(vm, "vm can not get resources: #{vm.error_msg} \n"\
                           "The group also has no resources to alloced rest #{vm_group.instances - num} vm")
          #Add failure vm to failure_vms que
          #@vm_lock.synchronize { @failure_vms[vm.name] = vm}
          return 'next rp'
        else
          group_place << vm
          #@logger.debug("Add #{vm.name} to preparing vms")
          @vm_lock.synchronize { @preparing_vms[vm.name] = vm }
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
        vm_group.req_rps.each { |cluster_name, rps|
          cluster = dc_resource.clusters[cluster_name]
          cluster_resource_pools = cluster.resource_pools
          place_rp = cluster_resource_pools.select {|k, v| rps.include?(k)}.values
          need_next_rp = nil
          hosts = hosts_prepare_in_cluster(cluster)

          set_best_placement_rp_list!(place_rp)

          loop_resource(place_rp) {|resource_pool|
            need_next_rp = vm_group_placement(vm_group, group_place, hosts, resource_pool)
            next if need_next_rp
            break
          }
          break unless need_next_rp
        }
        if need_next_rp
          ## can not alloc vm_group anymore
          #TODO add code here
        end
        vm_placement << group_place
      }

      vm_placement
    end

    def loop_resource(res)
      while (!res.empty?)
        if !yield res.first
          res.shift
        end
        res.rotate!
      end
    end

  end
end
