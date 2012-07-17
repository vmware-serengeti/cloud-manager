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
    DEPLOY_GROUP_PARALLEL = "group_parallel"
    DEPLOY_GROUP_ORDER    = "group_order"
    DEPLOY_GROUP_POLICY   = [DEPLOY_GROUP_PARALLEL, DEPLOY_GROUP_ORDER]

    class Config
      def_const_value :deploy_policy,  DEPLOY_GROUP_PARALLEL
    end
    class Cloud
      include Serengeti::CloudManager::Parallel

      #TODO cluster_changes
      def cluster_deploy(cluster_changes, vm_placement, options={})
        policy = config.deploy_policy #@input_cluster_info['deploy_policy'] || DEPLOY_GROUP_POLICY.first
        policy.downcase!
        policy = DEPLOY_GROUP_POLICY.first if !DEPLOY_GROUP_POLICY.include?(policy)

        logger.debug("Enter cluster_deploy policy: #{policy}")

        #Begin to parallel deploy vms
        unless cluster_changes.empty?
          cluster_changes.each do |group|
            group_each_by_threads(group, :callee=>'deploy changes', :order=>(policy==DEPLOY_GROUP_ORDER)) do |vm|
              #TODO add change code here
              logger.info("Changed vm #{vm.pretty_inspect}")
              vm.status = VM_STATE_DONE
            end
          end
          logger.info("Finish all changes")
        end

        order = ( policy == DEPLOY_GROUP_ORDER )
        group_each_by_threads(vm_placement, :order => order, :callee => 'deploy group') do |group|
          group_each_by_threads(group, :callee=>'deploy vms') do |vm|
            if (vm.error_code.to_i != 0)
              logger.debug("VM #{vm.name} can not deploy because:#{vm.error_msg}.")
              next
            end
            vm.deploy()
          end
        end

        logger.info("Finish all deployments")
        "finished"
      end

      ###################################
      # inner used functions
      def gen_disk_name(datastore, vm, type, unit_number)
        "[#{datastore.name}] #{vm.name}/#{type}-disk-#{unit_number}.vmdk"
      end

    end
  end
end
