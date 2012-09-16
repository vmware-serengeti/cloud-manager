###############################################################################
#   Copyright (c) 2012 VMware, Inc. All Rights Reserved.
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
          {'require' => 'plugin/resource_network', 'obj' => 'ResourceNetwork'},
          {'require' => 'plugin/resource_ft', 'obj' => 'ResourceFT'},
          {'require' => 'plugin/resource_ha', 'obj' => 'ResourceHA'}, ]
      def_const_value :placement_rp_place_enable, true
    end

    class PlacementService
      include Serengeti::CloudManager::Utils
      def initialize(cloud)
        @rc_services = {}
        @place_engine = cloud.create_service_obj(config.placement_engine.first, cloud) # Currently, we only use the first engine
        raise ParameterException "place engine can not create" if @place_engine.nil?
        load_res_service(cloud, @rc_services)
        @vm_placement = {}
        @vm_placement[:failed_num] = 0
        @vm_placement[:error_msg] = []
        @vm_placement[:action] = []
        @cloud = cloud
      end

      def service(name)
        @rc_services[name]
      end

      def services
        @rc_services
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

      # TODO get hosts without resource pool support.
      # Not Finished
      def group_placement(dc_resource, vm_groups)
        hosts = []
        vm_groups.each do |vm_group|

        end
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

      def create_vm_instances(specs, scores, selected_host)
        logger.debug("specs:#{specs}")
        vms = []
        specs.each_index do |idx|
          spec = specs[idx]
          vm = VmInfo.new(spec['name'], cloud)
          cluster_hosts = cloud.hosts
          host = cluster_hosts[selected_host]
          res_vms = Hash[scores.map { |name, score| [name, score[selected_host][idx]] } ]
          vm.assign_resources(spec, host, res_vms, services)
          vms << vm
        end
        vms
      end

      def remove_empty_scores!(scores)
        scores.each do |name, score|
          score.each do |host, value|
            if value.nil?
              logger.warn("remove host:#{host} for #{name} service can not support it")
              next scores.each_value { |score_| score_.delete(host) }
            end
          end
        end
        scores.first[1].size
      end


      def place_group_vms_with_hosts(hosts, virtual_group, existed_vms, placed_vms)
        group_place = []
        virtual_nodes = @place_engine.get_virtual_nodes(virtual_group, existed_vms, placed_vms)
        return [] if virtual_nodes.empty?
        all_hosts = hosts

        logger.debug("vns:#{virtual_nodes.pretty_inspect}")

        virtual_nodes.each do |vnode|
          vm = VmServer.new
          logger.debug("vnode:#{vnode.pretty_inspect}")
          specs = vnode.map { |spec| spec.to_spec }
          service_loop { |service| vm.init_with_vm_service(service, specs) }

          # Check capacity
          logger.debug("Check capacity: #{hosts.pretty_inspect}")
          service_loop do |service|
            logger.debug("check service name: #{service.name}")
            hosts = service.check_capacity(vm.vm(service.name), hosts)
            logger.debug("after #{service.name} check: #{hosts.pretty_inspect}")
            raise PlacementException, "Do not find any hosts can match resources requirement after #{service.name} check" if hosts.nil?
          end

          # Each service calc their values
          scores = {}
          service_loop do |service|
            # service will return {host1=>vm1, host2=>vm2}
            scores[service.name] = service.evaluate_hosts(vm.vm(service.name), hosts)
          end

          sore_size = remove_empty_scores!(scores)
          raise PlacementException, 'placement engine can not place those vnodes' if sore_size <= 0

          #logger.debug("scores: #{scores.pretty_inspect}")
          # place engine to decide how to place

          success = true
          selected_host = nil
          loop do
            selected_host = @place_engine.select_host(vnode, scores, all_hosts)
            raise PlacementException,'Do not select suitable host' if selected_host.nil?
            logger.debug("host select :#{selected_host}")

            committed_service = []
            service_loop do |service|
              success = service.commit(scores[service.name][selected_host])
              if success
                committed_service.unshift(service)
              else
                # Fail to commit service
                success = false
                committed_service.each { | commit | commit.discommit(scores[service.name][selected_host]) }
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
            @place_engine.assign_host(vnode, selected_host)

            # PLACE VM, just for fast devlop. It will remove, if finish vm's deploy service
            vms = create_vm_instances(specs, scores, selected_host)

            vms.each { |vm| cloud.state_sub_vms_set_vm(:placed, vm) }
            group_place << vms
          end
        end
        group_place = group_place.flatten.compact
        #logger.debug("group_place:#{group_place.pretty_inspect}")
        group_place
      end

      def cluster_placement(dc_resource, vm_groups_input, vm_groups_existed)
        @vm_placement[:failed_num] = 0
        @vm_placement[:error_msg] = []
        @vm_placement[:action] = []
        @vm_placement[:rollback] = nil

        # act_vms = { :action => {'action1' => [act1, act2, act3], }, {'action2' => [...]}, :rollback = nil... }
        act_vms = @place_engine.pre_placement_cluster(vm_groups_input, cloud.state_sub_vms(:existed))
        if (!act_vms.nil?) && (act_vms.size > 0)
          @vm_placement[:action] = act_vms[:action]
          @vm_placement[:rollback] = act_vms[:rollback]
          return @vm_placement
        end

        info = { :dc_resource => dc_resource, :vm_groups => vm_groups_input, :place_service => self }
        service_loop { |service| service.init_self(info) }

        @place_engine.placement_init(self, dc_resource)
        virtual_groups = @place_engine.get_virtual_groups(vm_groups_input)

        group_place = []
        virtual_groups.each do |gp_name, virtual_group|
          # check information and check error
          place_err_msg = nil
          # Group's Resource pool check.
          hosts = []
          # hosts' info is [hostname1, hostname2, ... ]
          if config.placement_rp_place_enable
            logger.debug("vg_name: #{gp_name}")
            place_rps = group_placement_rps(dc_resource, virtual_group.to_vm_groups)
            next if place_rps.nil?
            logger.debug("place_rps: #{place_rps.pretty_inspect}")

            hosts = place_rps.map { |rp| rp.cluster.hosts.values.map { |h| h.name } }.flatten.uniq
          else
            hosts = group_placement(dc_resource, virtual_group.to_vm_groups)
          end

          begin
            group_place = place_group_vms_with_hosts(hosts, virtual_group,
                                    cloud.state_sub_vms(:existed),
                                    cloud.state_sub_vms(:placed))
          rescue PlacementException => e
            ## can not alloc virual_group anymore
            error_msg = "Can not alloc resource for vm group #{gp_name}: #{e.message}"
            set_placement_error_msg(error_msg)
            @vm_placement[:failed_num] += 1
            logger.error("VM group #{gp_name} failed to place vm, "\
                         "total failed: #{@vm_placement[:failed_num]}.") if config.debug_placement
            raise error_msg
          end
          logger.debug("out group_place vms placement")
          group_place.each { |vm| logger.debug("#{vm.name} => h:#{vm.host_name} r:#{vm.rack}") }
          @vm_placement[:action] << { 'act' => 'group_deploy', 'group' => group_place }
        end

        @vm_placement[:action].unshift({ 'act' => 'create_vm_folders', 'group' => vm_groups_input})
        #logger.debug("vm_placement: #{@vm_placement[:action].pretty_inspect}" )
        logger.debug("vm_placement vms group placement")
        @vm_placement[:action].each { |g| log_group_place(g['group']) if g['act'] == 'group_deploy' }
        logger.obj2file(@vm_placement, 'vm_placement_2')
        @vm_placement
      end

      def log_group_place(group_place)
        #logger.debug("group_place: #{group_place.pretty_inspect}")
        group_place.each { |vm| logger.debug("#{vm.name} => h:#{vm.host_name} r:#{vm.rack}") }
      end
    end

  end
end
