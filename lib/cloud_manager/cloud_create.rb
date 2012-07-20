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

    class Config
      def_const_value :deploy_retry_num, 1
    end

    class Cloud
      attr_accessor :vm_groups_existed
      attr_accessor :vm_groups_input
      def create_and_update(cloud_provider, cluster_info, cluster_data, task)
        action_process(CLOUD_WORK_CREATE, task) do
          logger.info("enter create_and_update...")
          create_cloud_provider(cloud_provider)
          @vm_lock.synchronize { state_vms_init }
          #logger.debug("#{cluster_info.inspect}")
          cluster_changes = []

          dc_resources      = {}
          vm_groups_existed = {}
          vm_groups_input   = {}
          begin
            result = prepare_working(cluster_info, cluster_data)
            @dc_resources = dc_resources = result[:dc_res]
            vm_groups_existed = result[:group_existed]
            vm_groups_input   = result[:group_input]

            # Create existed vm groups
            unless vm_groups_existed.empty?
              # Checking and do difference
              @status = CLUSTER_UPDATE
              nodifference, cluster_changes = cluster_diff(dc_resources, vm_groups_input, vm_groups_existed)
              if nodifference
                logger.debug("No difference here")
                @status = CLUSTER_DONE
              else
                logger.obj2file(cluster_changes, 'cluster_changes')
              end
            end
          rescue => e
            logger.error("Prepare working failed.")
            logger.debug("#{e} - #{e.backtrace.join("\n")}")
            cluster_failed(task)
            #TODO add all kinds of error handlers here
            raise e
          end
          if @status == CLUSTER_DONE
            cluster_done(task)
            logger.info("No difference found, finish work.")
            return
          end

          retry_num = config.deploy_retry_num

          retry_num.times do |cycle_num|
            begin
              ###########################################################
              #Caculate cluster placement
              logger.info("Begin placement")
              @status = CLUSTER_PLACE
              place_obj = PlacementService.new(self)
              placement = place_obj.cluster_placement(dc_resources, vm_groups_input, vm_groups_existed)
              @placement_failed = placement[:failed_num]
              if placement[:error_msg].size > 0
                placement[:error_msg].each { |m| set_cluster_error_msg(m) }
                raise 'placement failed!'
              end
              logger.obj2file(placement, 'placement')

              logger.info("Begin deploy")

              #Begin cluster deploy
              @status = CLUSTER_DEPLOY
              successful = cluster_deploy(cluster_changes, placement[:place_groups])

              logger.info("Begin waiting cluster ready")
              #Wait cluster ready
              @status = CLUSTER_WAIT_START
              successful = cluster_wait_ready(state_sub_vms(:existed).values)
              break if successful

              @status = CLUSTER_RE_FETCH_INFO
              dc_resources = @resources.fetch_datacenter(@cloud_provider.vc_datacenter, cluster_info['template_id'])
              #TODO add all kinds of error handlers here
              logger.info("reload datacenter resources from cloud")

              logger.obj2file(dc_resources, "dc_resource-#{cycle_num}")
            rescue => e
              logger.warn("#{e} - #{e.backtrace.join("\n")}")
              if cycle_num + 1  >= retry_num
                cluster_failed(task)
                raise
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
