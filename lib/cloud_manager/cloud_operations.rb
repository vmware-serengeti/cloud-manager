module Serengeti
  module CloudManager
    class Cloud
      CLUSTER_ACTION_MESSAGE = {
        CLUSTER_DELETE => 'delete',
        CLUSTER_START  => 'start',
        CLUSTER_STOP   => 'stop',
      }

      def vhelper_vm_op(cloud_provider, cluster_info, task, action)
        act = CLUSTER_ACTION_MESSAGE[action]
        act = 'unknown' if act.nil?
        @logger.info("enter #{act} cluster ... ")
        create_cloud_provider(cloud_provider)
        dc_resources, vm_groups_existed, vm_groups_input = prepare_working(cluster_info)

        @status = action 
        matched_vms = dc_resources.clusters.values.map {|cs| cs.vms.values.select{|vm| vm_is_this_cluster?(vm.name)} }
        matched_vms.flatten!

        @logger.debug("#{matched_vms.pretty_inspect}")
        @logger.debug("vms name: #{matched_vms.collect{|vm| vm.name}.pretty_inspect}")
        yield matched_vms
        cluster_done(task)

        @logger.debug("#{act} all vm's")
      end

      def list_vms(cloud_provider, cluster_info, cluster_data, task)
        action_process (CLOUD_WORK_LIST) do
          @logger.debug("enter list_vms...")
          create_cloud_provider(cloud_provider)
          dc_resources, vm_groups_existed, vm_groups_input = prepare_working(cluster_info)
          cluster_done(task)
        end
        get_result.servers
      end

      def delete(cloud_provider, cluster_info, cluster_data, task)
        action_process (CLOUD_WORK_DELETE) do
          vhelper_vm_op(cloud_provider, cluster_info, task, CLUSTER_DELETE) do |vms|
            group_each_by_threads(vms) do |vm|
              vm.action = VM_ACTION_DELETE
              #@logger.debug("Can we delete #{vm.name} same as #{cluster_info["name"]}?")
              #@logger.debug("vm split to #{@cluster_name}::#{result[2]}::#{result[3]}")
              @logger.debug("delete vm : #{vm.name}")
              vm.status = VM_STATE_DELETE
              next if !vm_deploy_op(vm, 'delete') { @client.vm_destroy(vm) }
              vm.status = VM_STATE_DONE
              vm_finish(vm)
            end
          end
        end
        cluster_done(task)
      end

      def start(cloud_provider, cluster_info, cluster_data, task)
        action_process(CLOUD_WORK_START) do
          vhelper_vm_op(cloud_provider, cluster_info, task, CLUSTER_START) do |vms|
            vms.each {|vm| vm.action = VM_ACTION_START}
            cluster_wait_ready(vms)
          end
        cluster_done(task)
        end
      end

      def stop(cloud_provider, cluster_info, cluster_data, task)
        action_process(CLOUD_WORK_STOP) do
          vhelper_vm_op(cloud_provider, cluster_info, task, CLUSTER_STOP) do |vms|
            group_each_by_threads(vms) do |vm|
              vm.action = VM_ACTION_STOP
              @logger.debug("stop :#{vm.name}")
              vm.status = VM_STATE_POWER_OFF

              next if !vm_deploy_op(vm, 'stop') { @client.vm_power_off(vm) }
              next if !vm_deploy_op(vm, 'reRead') {@client.update_vm_properties_by_vm_mob(vm)}
              vm.status = VM_STATE_DONE
              vm_finish(vm)
            end
          end
          cluster_done(task)
        end
      end

    end
  end
end
