module VHelper::CloudManager
  class VHelperCloud
    def cluster_datastore_pattern(cluster_info, type)
      if type == 'shared'
        return cluster_info["vc_shared_datastore_pattern"]
      elsif type == 'local'
        return cluster_info["vc_local_datastore_patten"]
      end
      nil
    end
    def create_vm_group_from_vhelper_input(cluster_info, datacenter_name)
      vm_groups = {}
      @logger.debug("cluster_info: #{cluster_info.pretty_inspect}")
      vhelper_groups = cluster_info["groups"]
      template_id = "/Datacenters/#{datacenter_name}/vm/#{cluster_info["template_id"]}"
      cluster_req_rps = @vc_req_rps
      cluster_req_rps = req_clusters_rp_to_hash(cluster_info["vc_clusters"]) if cluster_info["vc_clusters"]
      @logger.debug("template_id:#{template_id}")
      vhelper_groups.each { |vm_group_req|
        vm_group = VmGroupInfo.new(@logger, vm_group_req, template_id)
        vm_group.req_info.disk_pattern = cluster_datastore_pattern(cluster_info, vm_group.req_info.disk_type) if vm_group.req_info.disk_pattern.nil?
        vm_group.req_rps = cluster_req_rps
        vm_group.req_rps = req_clusters_rp_to_hash(vm_group_req["vc_clusters"]) if vm_group_req["vc_clusters"]
        vm_groups[vm_group.name] = vm_group
      }
      @logger.debug("vhelper_group:#{vm_groups}")
      vm_groups
    end

    def create_vm_group_from_resources(dc_res, vhelper_cluster_name)
      vm_groups = {}
      dc_res.clusters.each_value do |cluster|
        cluster.vms.each_value do |vm|
          @logger.debug("vm :#{vm.name}")
          result = get_from_vm_name(vm.name) 
          next unless result
          cluster_name = result[1]
          group_name = result[2]
          num = result[3]
          @logger.debug("vm split to #{cluster_name}::#{group_name}::#{num}")
          next if (cluster_name != vhelper_cluster_name)
          vm_group = vm_groups[group_name]
          if vm_group.nil?
            vm_group = VmGroupInfo.new(@logger)
            vm_groups[group_name] = vm_group
          end
          vm_group.add_vm(vm)
          add_existed_vm(vm)
        end
      end
      #@logger.debug("res_group:#{vm_groups}")
      vm_groups
    end

  end
end

