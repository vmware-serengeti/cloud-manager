module VHelper::CloudManager
  class VHelperCloud
    def cluster_placement(dc_resource, vm_groups_input, vm_groups_existed, cluster_info)
      vm_placement = []
      if vm_groups_existed.size > 0
        #TODO add changed placement logical
      end
      
      #TODO add placement logical here
      vm_groups_input.each_value do |vm_group|
        group_place = []
        looptimes = vm_group.instances.to_i
        looptimes.times do |num|
          vm_name = gen_vm_name(cluster_info["name"], vm_group.name, num)
          @logger.debug("vm_name: #{vm_name}")
          vm = VHelper::CloudManager::VmInfo.new(vm_name, @logger)
          @logger.debug("dc:#{dc_resource.pretty_inspect}")
          cluster = dc_resource.clusters.values.first
          host = cluster.hosts.values.first
          vm.host_name = host.name 
          vm.host_mob = host.mob
          sys_datastore = host.share_datastores.values.first
          vm.sys_datastore_moid = sys_datastore.mob
          vm.resource_pool_moid = cluster.resource_pool_moid    
          vm.template_id = vm_group.req_info.template_id
          fullpath = "[#{sys_datastore.name}] #{vm_name}/data.vmdk" 
          vm.disk_add(vm_group.req_info.disk_size, fullpath)

          group_place << vm
        end
        vm_placement << group_place
      end

      vm_placement
    end
  end
end
