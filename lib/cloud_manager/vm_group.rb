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
# @author haiyu wang

module Serengeti
  module CloudManager

    class Cloud
      def cluster_datastore_pattern(cluster_info, type)
        if type == 'shared'
          return cluster_info["vc_shared_datastore_pattern"]
        elsif type == 'local'
          return cluster_info["vc_local_datastore_pattern"]
        end
        nil
      end

      # fetch vm_group information from user input (cluster_info)
      # It will assign template/rps/networking/datastores info to each vm group
      # Return: the vm_group structure
      def create_vm_group_from_serengeti_input(cluster_info, datacenter_name)
        vm_groups = {}
        #@logger.debug("cluster_info: #{cluster_info.pretty_inspect}")
        input_groups = cluster_info["groups"]
        template_id = cluster_info["template_id"] #currently, it is mob_ref
        raise "template_id should a vm mob id (like vm-1234)" if /^vm-[\d]+$/.match(template_id).nil?
        cluster_req_rps = @vc_req_rps
        cluster_req_rps = req_clusters_rp_to_hash(cluster_info["vc_clusters"]) if cluster_info["vc_clusters"]
        cluster_networking = cluster_info["networking"]
        #@logger.debug("networking : #{cluster_networking.pretty_inspect}")

        network_res = NetworkRes.new(cluster_networking)
        #@logger.debug("dump network:#{network_res}")
        @logger.debug("template_id:#{template_id}")
        input_groups.each do |vm_group_req|
          vm_group = VmGroupInfo.new(vm_group_req)
          vm_group.req_info.template_id ||= template_id
          disk_pattern = vm_group.req_info.disk_pattern || cluster_datastore_pattern(cluster_info, vm_group.req_info.disk_type)
          @logger.debug("vm_group disk patterns:#{disk_pattern.pretty_inspect}")

          vm_group.req_info.disk_pattern = []
          disk_pattern = ['*'] if disk_pattern.nil?
          vm_group.req_info.disk_pattern = change_wildcard2regex(disk_pattern).map { |x| Regexp.new(x) }
          @logger.debug("vm_group disk ex patterns:#{vm_group.req_info.disk_pattern.pretty_inspect}")

          vm_group.req_rps = (vm_group_req["vc_clusters"].nil?) ? cluster_req_rps : req_clusters_rp_to_hash(vm_group_req["vc_clusters"])
          vm_group.network_res = network_res
          vm_groups[vm_group.name] = vm_group
        end
        #@logger.debug("input_group:#{vm_groups}")
        vm_groups
      end

      # fetch vm_group information from dc resources came from vSphere (dc_res)
      # It will assign existed vm to each vm group, and put them to VM_STATE_READY status.
      # Return: the vm_group structure
      def create_vm_group_from_resources(dc_res, serengeti_cluster_name)
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
            next if (cluster_name != serengeti_cluster_name)
            vm_group = vm_groups[group_name]
            if vm_group.nil?
              vm_group = VmGroupInfo.new()
              vm_group.name = group_name
              vm_groups[group_name] = vm_group
            end
            vm.status = VM_STATE_READY
            vm_group.add_vm(vm)
            add_2existed_vm(vm)
          end
        end
        #@logger.debug("res_group:#{vm_groups}")
        vm_groups
      end
    end

    # This structure contains the group information
    class VmGroupInfo
      attr_accessor :name       #Group name
      attr_accessor :req_info   #class ResourceInfo
      attr_reader   :vc_req
      attr_accessor :instances  #wanted number of instance
      attr_accessor :req_rps
      attr_accessor :network_res
      attr_accessor :vm_ids    #classes VmInfo
      def initialize(rp=nil)
        @logger = Serengeti::CloudManager::Cloud.Logger
        @vm_ids = {}
        @req_info = ResourceInfo.new(rp)
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
end

