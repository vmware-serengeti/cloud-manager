module VHelper::CloudManager
  class VHelperCloud
    def gen_vm_name(cluster_name, group_name, num)
      return "#{cluster_name}-#{group_name}-#{num}"
    end

    def get_from_vm_name(vm_name)
      return /([\w\s\d]+)\-([\w\s\d]+)([\d]+)/.match(vm_name)
    end

    def create_vm_group_from_vhelper_input(cluster_info)
      vm_groups = {}
      @logger.debug("cluster_info: #{cluster_info.pretty_inspect}")
      vhelper_groups = cluster_info["groups"]
      vhelper_groups.each do |vm_group_req|
        vm_group = VmGroupInfo.new(@logger, vm_group_req, cluster_info["template_id"])
        vm_groups[vm_group.name] = vm_group
      end
      @logger.debug("vhelper_group:#{vm_groups}")
      vm_groups
    end

    def create_vm_group_from_resources(dc_res)
      vm_groups = {}
      dc_res.clusters.each_value do |cluster|
        cluster.vms.each_value do |vm|
          @logger.debug("vm :#{vm.name}")
          result = get_from_vm_name(vm.name)
          next unless result
          cluster = result[1]
          group_name = result[2]
          host_name = result[3]
          num = result[4]
          @logger.debug("vm split to #{cluster}::#{group_name}::#{num}")
          vm_group = vm_groups[group_name]
          if vm_group.nil?
            vm_group = VmGroupInfo.new(@logger)
            vm_groups[group_name] = vm_group
          end
          vm_group.add_vm(vm)
          add_existed_vm(vm)
        end
      end
      @logger.debug("res_group:#{vm_groups}")
      vm_groups
    end

  end
end

