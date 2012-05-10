module VHelper::CloudManager
  class VHelperCloud
    def create_and_update(cloud_provider, cluster_info, task)
      action_process (CLOUD_WORK_CREATE) {
        @logger.debug("enter create_and_update...")
        create_cloud_provider(cloud_provider)
        @vm_lock.synchronize {
          @deploy_vms = {}
          @existed_vms = {}
          @preparing_vms = {}
          @failure_vms = {}
          @finished_vms = {}
        }
        #FIXME we only support one cluster, currently

        #@logger.debug("#{cluster_info.inspect}")
        @logger.debug("Begin vHelper work...")
        cluster_changes = []

        begin
          dc_resources, vm_groups_existed, vm_groups_input = prepare_working(cluster_info)
          ###########################################################
          # Create existed vm groups

          unless vm_groups_existed.empty?
            ###########################################################
            #Checking and do difference
            @status = CLUSTER_UPDATE
            nodifference, cluster_changes = cluster_diff(dc_resources, vm_groups_input, vm_groups_existed)
            if nodifference
              @logger.info("No difference here")
              @status = CLUSTER_DONE
            else
              log_obj_to_file(cluster_changes, 'cluster_changes')
            end
          end
        rescue => e
          @logger.debug("Prepare working failed.")
          @logger.debug("#{e} - #{e.backtrace.join("\n")}")
          cluster_failed(task)
          #TODO add all kinds of error handlers here
          raise e
        end
        if @status == CLUSTER_DONE
          cluster_done(task)
          @logger.info("No work need to do!")
          return
        end

        retry_num = 1

        retry_num.times do |cycle_num|
          begin
            ###########################################################
            #Caculate cluster placement
            @logger.debug("Begin placement")
            @status = CLUSTER_PLACE
            placement = cluster_placement(dc_resources, vm_groups_input, vm_groups_existed, cluster_info)
            log_obj_to_file(placement, 'placement')

            if template_placement?
              @status = CLUSTER_TEMPLATE_PLACE
              template_place = template_placement(dc_resources, cluster_info, vm_groups_input, placement)
              log_obj_to_file(template_place, 'template_place')
              cluster_deploy([], template_place)
            end

            @logger.debug("Begin deploy")
            #Begin cluster deploy
            @status = CLUSTER_DEPLOY
            successful = cluster_deploy(cluster_changes , placement)

            #Wait cluster ready
            @status = CLUSTER_WAIT_START
            successful = cluster_wait_ready(@existed_vms.values)
            break if successful

            @status = CLUSTER_RE_FETCH_INFO
            dc_resources = @resources.fetch_datacenter
            #TODO add all kinds of error handlers here
            @logger.info("reload datacenter resources from cloud")

            log_obj_to_file(dc_resources, "dc_resource-#{cycle_num}")
          rescue => e
            @logger.debug("#{e} - #{e.backtrace.join("\n")}")
            if cycle_num + 1  >= retry_num
              cluster_failed(task)
              raise
            end
            @logger.debug("Loop placement faild and retry #{cycle_num} loop")
          end
        end
        ###########################################################
        # Cluster deploy successfully
        cluster_done(task)
      }
    end


  end
end
