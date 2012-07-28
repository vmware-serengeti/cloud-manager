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
module Serengeti
  module CloudManager

    class RRPlacement < Placement
      class Node
        def initialize(vm_group, name)
          @vm_group = vm_group
          @name = name
        end
        def to_spec
          spec = @vm_group.to_spec
          spec['name'] = @name
          spec
        end
      end

      ############################################################
      # Only RR for rps/hosts/datastores selected
      def get_virtual_groups(vm_groups)
        vm_groups
      end

      def initialize(cloud)
        super
        @hosts = {}
      end

      def pre_placement_cluster(vm_groups, existed_vms)
        nil
      end

      def get_virtual_nodes(virtual_group, existed_vms, placed_vms)
        vm_spec_groups = []
        (0...virtual_group.instances).each do |num|
          vm_name = gen_cluster_vm_name(virtual_group.name, num)
          next if existed_vms.key?(vm_name)
          next if placed_vms.key?(vm_name)

          spec = Node.new(virtual_group, vm_name)
          vm_spec_groups << [spec]
        end
        vm_spec_groups
      end

      def scores2_host(scores)
        scores_host = {}
        scores.each do |name, score|
          score.each do |host, value|
            scores_host[host] = {} if scores_host[host].nil?
            scores_host[host][name] = value
          end
        end
        scores_host
      end

      def select_host(vms, scores)
        scores = scores2_host(scores)
        mini_host = nil
        scores.each_key do |host|
          if @hosts.key?(host)
            mini_host = host if mini_host.nil?
            logger.debug("mini: #{@hosts[mini_host]} #{@hosts[host]}")
            mini_host = host if @hosts[mini_host] > @hosts[host]
          else
            @hosts[host] = 1
            return host
          end
        end
        mini_host
      end

      def assign_host(vms, host)
        @hosts[host] += 1 if @hosts.key?(host)
      end

    end
  end
end
