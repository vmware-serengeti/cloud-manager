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

    class Config
      def_const_value :deploy_retry_num, 0
    end

    class Cloud
      attr_accessor :vm_groups_existed
      attr_accessor :vm_groups_input

      def create()
        cloud_provider, cluster_info, cluster_data, task = @cloud_provider, @cluster_info, @cluster_last_data, @task
        action_process(CLOUD_WORK_CREATE, task) do
          logger.info("enter create_and_update...")
          create_cloud_provider(cloud_provider)
          @vm_lock.synchronize { state_vms_init }
          #logger.debug("#{cluster_info.inspect}")

          retry_num = config.deploy_retry_num
          cycle_num = 0
          loop do
            begin
              if cycle_num > retry_num
                logger.debug("#{cycle_num} cycles, leave retry loop")
                break
              end
              ###########################################################
              #Caculate cluster placement
              result = prepare_working(cluster_info, cluster_data)
              @dc_resources = result[:dc_res]

              vm_groups_existed = result[:group_existed]
              vm_groups_input   = result[:group_input]

              logger.info("Begin placement")
              @status = CLUSTER_PLACE
              place_obj = PlacementService.new(self)
              placement = place_obj.cluster_placement(@dc_resources, vm_groups_input, vm_groups_existed)
              @placement_failed = placement[:failed_num]
              if placement[:error_msg].size > 0
                placement[:error_msg].each { |m| set_cluster_error_msg(m) }
                raise 'placement failed!'
              end
              logger.obj2file(placement, 'placement')

              #Begin cluster deploy
              logger.info("Begin deploy")
              @status = CLUSTER_DEPLOY
              successful = cluster_deploy(placement[:action])
              next if placement[:rollback] == 'fetch_info'

              logger.info("Begin waiting cluster ready")
              #Wait cluster ready
              @status = CLUSTER_WAIT_START
              successful = cluster_wait_ready(state_sub_vms(:existed).values, :force_power_on => true)
              break if successful

              @status = CLUSTER_RE_FETCH_INFO
              logger.info("reload datacenter resources from cloud")

              logger.obj2file(@dc_resources, "dc_resource-roll-back-#{cycle_num}")
              cycle_num += 1
            rescue => e
              logger.warn("#{e} - #{e.backtrace.join("\n")}")
              cycle_num += 1
              if cycle_num >= retry_num
                logger.warn("Loop placement faild #{cycle_num} loop")
                raise e
              end
              logger.warn("Loop placement faild and retry #{cycle_num} loop")
            end
          end
          ###########################################################
          # Cluster deploy successfully
        end

      end
    end

  end
end
