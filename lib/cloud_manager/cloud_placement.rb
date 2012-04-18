module VHelper::CloudManager
  class VHelperCloud
    REMAIDER_DISK_SIZE = ResourceInfo::DISK_CHANGE_TIMES * 10
    HOST_SYS_DISK_SIZE = ResourceInfo::DISK_CHANGE_TIMES * 2

    def get_suitable_resource_pool(resource_pools, req_info)
      resource_pools.each_value { |rp|
        if rp.limit_mem != -1 && (rp.real_free_memory < req_info.mem)
          @logger.debug("limit:#{rp.limit_mem},real_free:#{rp.real_free_memory}, req:#{req_info.mem}")
          next
        end
        return rp
      }
      nil
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

    def alloc_res(vm, vm_group, cur_rp, sys_datastore, host, used_datastores)
      req_mem = vm_group.req_info.mem
      cur_rp.unaccounted_memory += req_mem
      host.unaccounted_memory += req_mem

      vm.host_name  = host.name 
      vm.host_mob   = host.mob
      vm.req_rp     = vm_group.req_info

      vm.sys_datastore_moid = sys_datastore.mob
      vm.resource_pool_moid = cur_rp.mob
      vm.template_id = vm_group.req_info.template_id

      used_datastores.each { |datastore|
        fullpath = "[#{datastore[:datastore].name}] #{vm.name}/data.vmdk" 
        datastore[:datastore].unaccounted_space += datastore[:size].to_i
        vm.disk_add(datastore[:size].to_i, fullpath)
      }
    end

    def cluster_placement(dc_resource, vm_groups_input, vm_groups_existed, cluster_info)
      vm_placement = []
      if vm_groups_existed.size > 0
        #TODO add changed placement logical
      end

      #TODO add placement logical here
      cluster = dc_resource.clusters.values.first
      resource_pools = cluster.resource_pools

      @logger.debug("#{cluster.hosts.pretty_inspect}")
      vm_groups_input.each_value { |vm_group|
        hosts = cluster.hosts.values
        #@logger.debug("#{hosts.class},#{hosts.pretty_inspect}")
        hosts.shuffle!

        #Check and find suitable resource_pool
        cur_rp = get_suitable_resource_pool(resource_pools, vm_group.req_info)
        raise "No resources for placement!" if cur_rp.nil?

        hosts.each { |host|
          host.place_share_datastores = host.share_datastores.values
          host.place_local_datastores = host.local_datastores.values
          host.place_share_datastores.shuffle!
          host.place_local_datastores.shuffle!
        }

        group_place = []
        vm_group.instances.times { |num|
          vm_name = gen_vm_name(cluster_info["name"], vm_group.name, num)
          @logger.debug("vm_name: #{vm_name}")
          vm = VHelper::CloudManager::VmInfo.new(vm_name, @logger)
          vm.host_name = nil
          loop_hosts(hosts) { |host|
            req_mem = vm_group.req_info.mem
            #@logger.debug("req mem #{req_mem}  ===> host :#{host.inspect}")
            if host.real_free_memory < req_mem
              @logger.debug("#{host.name} haven't enough memory for #{vm_name} req:#{req_mem}, host has :#{host.real_free_memory}.")
              next
            end
            #The host is suitable for this VM
            host.place_share_datastores.rotate!

            #Get the sys_datastore for clone
            sys_datastore = get_suitable_sys_datastore(host.place_share_datastores)

            if sys_datastore.nil?
              @logger.debug("can not find suitable sys datastore in host #{host.name}.")
              next
            end
            @logger.debug("get sys datastore :#{sys_datastore.name}")

            #Get the datastore for this vm

            req_size = vm_group.req_info.disk_size
            used_datastores = get_suitable_datastores(host.place_share_datastores, req_size)
            if used_datastores.empty?
              #TODO no disk space for this vm
              vm.error_msg = "No enough disk for #{vm_name}."
              @logger.debug("ERROR: #{vm.error_msg}")
              # Remove this host
              next
            end
            #Find suitable Host and datastores
            alloc_res(vm, vm_group, cur_rp, sys_datastore, host, used_datastores)
            vm.error_msg = nil
            ## RR for next Host
            break
          }
          if vm.error_msg
            #NO resource for this vm_group
            vm.error_msg << "The group also has no resources to alloced"
            @logger.debug("vm can not get resources :#{vm.error_msg} ")
            #Add failure vm to failure_vms que
            @vm_lock.synchronize { @failure_vms[vm.name] = vm}
          else
            group_place << vm
            @logger.debug("Add #{vm.name} to preparing vms")
            @vm_lock.synchronize { @preparing_vms[vm.name] = vm }
          end
        }
        vm_placement << group_place
      }

      vm_placement
    end
    def loop_hosts(hosts)
      while (!hosts.empty?)
        if !yield hosts[0]
          hosts.shift
        end
        hosts.rotate!
      end
    end
  end
end
