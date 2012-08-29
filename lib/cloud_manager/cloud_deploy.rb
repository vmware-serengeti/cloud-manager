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

      def cluster_vm_group_deploy(group, options = {})
        group_each_by_threads(group, :callee=>'deploy vms') do |vm|
          logger.debug("deploy vm: #{vm.pretty_inspect}")
          if (vm.error_code.to_i != 0)
            logger.debug("VM #{vm.name} can not deploy because:#{vm.error_msg}.")
            next
          end
          vm.deploy()
        end
      end

      def cluster_vm_group_delete(group, options = {})
        group_each_by_threads(group, :callee=>'destory vm') { |vm| vm.delete }
      end

      def cluster_deploy(vm_placement, options={})
        policy = config.deploy_policy
        policy.downcase!
        policy = DEPLOY_GROUP_POLICY.first if !DEPLOY_GROUP_POLICY.include?(policy)

        logger.debug("Enter cluster_deploy policy: #{policy}")

        #Begin to parallel deploy vms
        order = ( policy == DEPLOY_GROUP_ORDER )
        group_each_by_threads(vm_placement, :order => order, :callee => 'deploy group') do |group|
          self.send("cluster_vm_#{group['act']}", group['group'], group)
        end

        logger.info("Finish all deployments")
        "finished"
      end

    end
  end
end
