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

# @since serengeti 0.5.1
# @version 0.5.1
module Serengeti
  module CloudManager
    class Config
      #def_const_value :placement_engine, [{'require' => 'plugin/placement_rr', 'obj' => 'RRPlacement'}]
      def_const_value :placement_engine, [{'require' => 'cloud_manager/placement_impl', 'obj' => 'FullPlacement'}]
      def_const_value :res_services,
        [ {'require' => 'plugin/resource_compute', 'obj' => 'ResourceCompute'},
          {'require' => 'plugin/resource_rp'  , 'obj' => 'ResourcePool'},
          {'require' => 'plugin/resource_storage', 'obj' => 'ResourceStorage'},
          {'require' => 'plugin/resource_network', 'obj' => 'ResourceNetwork'}, ]
    end

    class PlacementService < BaseObject
      class PlaceServiceException < PlacementException
      end

      def initialize(cloud)
        @rc_services = {}
        @place_engine = cloud.create_service_obj(config.placement_engine.first, cloud) # Currently, we only use the first engine
        raise ParameterException "place engine can not create" if @place_engine.nil?
        load_res_service(cloud, @rc_services)
        @vm_placement = {}
        @vm_placement[:failed_num] = 0
        @vm_placement[:error_msg] = []
        @vm_placement[:place_groups] = []
        @cloud = cloud
      end

      def service(name)
        @rc_services[name]
      end

      def cloud
        @cloud
      end

      def set_placement_error_msg(msg)
        @vm_placement[:error_msg] << msg
      end

      def check_service(service)
        raise ParameterException "registered service is null" if service.nil?
        raise ParameterException "registered service do not have name" if service.name.to_s.empty?
        raise ParameterException "registered service is existed" if @rc_services.has_key?(service.name)
      end

      def load_res_service(cloud, services)
        res_service = config.res_services
        res_service.each do | service_info |
          service = init_service(cloud.create_service_obj(service_info, cloud))
          services[service.name] = service
        end
      end

      def init_service(service)
        check_service(service)
        service
      end

      def service_loop()
        @rc_services.each_value { |service| yield service }
      end

      # Check resource pools
      def group_placement_rps(dc_res, vm_groups)
        place_rps = []
        vm_groups.each do |vm_group|
          place_rps = vm_group.req_rps.map do |cluster_name, rps|
            rps.map do |rp_name|
              dc_res.clusters[cluster_name].resource_pools[rp_name] if dc_res.clusters.key?(cluster_name)
            end
          end
        end
        place_rps = place_rps.flatten.compact
        if place_rps.nil? || place_rps.size == 0
          @vm_placement[:failed_num] += 1
          err_msg = "Can not get any resource pools for vm"
          logger.error(err_msg)
          set_placement_error_msg(err_msg)
          return nil
        end
        # FIXME, Currently, we just use the first rp
        place_rps
      end

      def create_vm_with_each_resource(virtual_nodes)
        vm_servers_group = []
        specs = virtual_nodes.each do |node| 
          vm = VmServer.new
          specs = node.map { |spec| spec.to_spec }
          service_loop { |service| vm.init_with_vm_service(service, specs) }
          vm_servers_group << { :vm => vm, :specs => specs, :vnode => node }
        end

        vm_servers_group
      end

      def create_vm_instances(group, scores, selected_host)
        logger.debug("specs:#{group[:specs]}")
        vms = []
        group[:specs].each_index do |idx|
          spec = group[:specs][idx] 
          vm = Serengeti::CloudManager::VmInfo.new(spec['name'], cloud)
          cluster_hosts = cloud.hosts
          host = cluster_hosts[selected_host]

          vm.res_vms = Hash[scores.map { |name, score| [name, score[selected_host][idx]] } ]
          vm.error_msg = nil

          #vm.sys_datastore_moid = 'datastore-6348'
          vm.sys_datastore_moid = service('storage').get_system_ds_moid(vm.res_vms['storage'])
          logger.debug("vm: system moid #{vm.sys_datastore_moid}")
          vm.resource_pool_moid = vm.res_vms['resource_pool'].rp.mob
          logger.debug("vm: resource pool moid #{vm.resource_pool_moid}")
          #vm.resource_pool_moid = vm.res_vms['resource_pool'].mobid
          vm.spec = spec
          vm.host_name  = host.name
          vm.host_mob   = host.mob
          vm.storage_service = service('storage')

          vm.network_config_json = vm.res_vms['network'].spec
          vm.network_res = vm.res_vms['network'].network_res
          logger.debug("vm network json: #{vm.network_config_json}")
          logger.debug("vm network port group: #{vm.network_res.port_group(0)}")

          vms << vm
        end
        vms
      end

      def place_group_vms_with_hosts(hosts, virtual_group, existed_vms, placed_vms)
        group_place = []
        # Return such like this [[vmSpec1, vmSpec2],[vmSpec3]] 
        virtual_nodes = @place_engine.get_virtual_nodes(virtual_group, existed_vms, placed_vms)

        # Return such like this [[vmServer1, vmServer2],[vmServer3]]
        #logger.debug("vns:#{virtual_nodes.pretty_inspect}")
        vm_servers_groups = create_vm_with_each_resource(virtual_nodes)

        vm_servers_groups.each do |group|
          # Check capacity
          logger.debug("Check capacity: #{hosts.pretty_inspect}")
          service_loop do |service|
            hosts = service.check_capacity(group[:vm].vm(service.name), hosts)
            logger.debug("after #{service.name} check: #{hosts.pretty_inspect}")
            raise PlaceServiceException,'Do not find hosts can match resources requirement' if hosts.nil?
          end

          # Each service calc their values
          scores = {}
          service_loop do |service|
            # Return value is {host1=>value1, host2=>value2}
            scores[service.name] = service.evaluate_hosts(group[:vm].vm(service.name), hosts)
          end

          #logger.debug("scores: #{scores.pretty_inspect}")
          logger.debug("scores: #{scores.pretty_inspect}")
          # place engine to decide how to place

          success = true
          selected_host = nil
          loop do
            selected_host = @place_engine.select_host(group[:vnode], scores)
            raise PlaceServiceException,'Do not select suitable host' if selected_host.nil?
            logger.debug("host select :#{selected_host}")

            committed_service = []
            service_loop do |service|
              success = service.commit(scores[service.name][selected_host])
              if success
                committed_service.unshift(service)
              else
                # Fail to commit service
                success = false
                committed_service.each { |plug| service.discommit(scores[service.name][selected_host]) }
                logger.debug("VM commit is failed.")
                break
              end
            end
            break if success
            scores.each_value { |score| score.delete(selected_host) }
            break if scores.empty?
          end

          if success
            logger.debug("assign to #{selected_host}")
            @place_engine.assign_host(group[:vnode], selected_host)
            #service_loop { |service| service.assigned(service.name, selected_host, scores[service.name][selected_host]) }

            # PLACE VM, just for fast devlop. It will remove, if finish vm's deploy service
            vms = create_vm_instances(group, scores, selected_host)

            vms.each { |vm| cloud.state_sub_vms_set_vm(:placed, vm) }
            group_place << vms
          end
        end
        group_place = group_place.flatten.compact
        logger.debug("group_place:#{group_place.pretty_inspect}")
        group_place
      end

      def cluster_placement(dc_resource, vm_groups_input, vm_groups_existed)
        @vm_placement[:failed_num] = 0
        @vm_placement[:error_msg] = []
        @vm_placement[:place_groups] = []
 
=begin
        delete_vms = @place_engine.clean_cluster(vm_groups_input, cloud.state_sub_vms(:existed))
        if (!delete_vms.nil?) && (delete_vms.size > 0)
        end
=end
        info = { :dc_resource => dc_resource, :vm_groups => vm_groups_input, :place_service => self }
        service_loop { |service| service.init_self(info) }

        @place_engine.placement_init(self, dc_resource)
        virtual_groups = @place_engine.get_virtual_groups(vm_groups_input)

        group_place = [] 
        virtual_groups.each_value do |virtual_group|
          # check information and check error
          place_err_msg = nil
          # Group's Resource pool check.
          place_rps = group_placement_rps(dc_resource, virtual_group.to_vm_groups)
          next if place_rps.nil?
          logger.debug("place_rps: #{place_rps.pretty_inspect}")

          # Get all hosts with paired info
          # hosts' info is [hostname1, hostname2, ... ]
          hosts = place_rps.map { |rp| rp.cluster.hosts.values.map { |h| h.name } }.flatten.uniq
          begin
            group_place = place_group_vms_with_hosts(hosts, virtual_group,
                                    cloud.state_sub_vms(:existed),
                                    cloud.state_sub_vms(:placed))
          rescue PlacementException => e
            ## can not alloc virual_group anymore
            set_placement_error_msg("Can not alloc resource for vm group #{virtual_group.name}: #{place_err_msg}")
            @vm_placement[:failed_num] += 1
            logger.error("VM group #{virtual_group.name} failed to place vm, "\
                          "total failed: #{@vm_placement[:failed_num]}.") if config.debug_placement
            raise
          end
          logger.debug("out group_place:#{group_place.pretty_inspect}")
          @vm_placement[:place_groups] << group_place
        end

        logger.debug("vm_placement: #{@vm_placement[:place_groups].pretty_inspect}" )
        logger.obj2file(@vm_placement, 'vm_placement_2')
        @vm_placement
      end
    end

  end
end

