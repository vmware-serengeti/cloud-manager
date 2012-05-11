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
      cluster_networking = cluster_info["networking"]
      @logger.debug("networking : #{cluster_networking.pretty_inspect}")

      network_res = NetworkRes.new(cluster_networking)
      @logger.debug("dump network:#{network_res}")
      @logger.debug("template_id:#{template_id}")
      vhelper_groups.each { |vm_group_req|
        vm_group = VmGroupInfo.new(@logger, vm_group_req, template_id)
        disk_pattern = vm_group.req_info.disk_pattern || cluster_datastore_pattern(cluster_info, vm_group.req_info.disk_type)
        #@logger.debug("disk patterns:#{disk_pattern.pretty_inspect}")

        vm_group.req_info.disk_pattern = []
        disk_pattern = ['*'] if disk_pattern.nil?
        vm_group.req_info.disk_pattern = change_wildcard2regex(disk_pattern).map {|x| Regexp.new(x)} unless disk_pattern.empty?

        vm_group.req_rps = cluster_req_rps
        vm_group.req_rps = req_clusters_rp_to_hash(vm_group_req["vc_clusters"]) if vm_group_req["vc_clusters"]
        vm_group.network_res = network_res
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
            vm_group.name = group_name
            vm_groups[group_name] = vm_group
          end
          vm_group.add_vm(vm)
          add_2existed_vm(vm)
        end
      end
      #@logger.debug("res_group:#{vm_groups}")
      vm_groups
    end
  end

  class VmGroupInfo
    attr_accessor :name
    attr_accessor :req_info  #class ResourceInfo
    attr_reader   :vc_req
    attr_accessor :instances
    attr_accessor :req_rps
    attr_accessor :network_res
    attr_accessor :vm_ids    #classes VmInfo
    def initialize(logger, rp=nil, template_id=nil)
      @logger = logger
      @vm_ids = {}
      @req_info = ResourceInfo.new(rp, template_id)
      @name = ""
      return unless rp
      @name = rp["name"]
      @instances = rp["instance_num"]
      @req_rps = {}
    end

    def size
      vm_ids.size
    end

    def del_vm(vm_name)
      vm_info = find_vm(vm_name)
      return nil unless vm_info
      vm_info.delete_all_disk

      @vm_ids.delete(vm_mob)
    end
    def add_vm(vm_info)
      if @vm_ids[vm_info.name].nil?
        @vm_ids[vm_info.name] = vm_info
      else
        @logger.debug("#{vm_info.name} is existed.")
      end
    end
    def find_vm(vm_name)
      @vm_ids[vm_name]
    end
  end

end

