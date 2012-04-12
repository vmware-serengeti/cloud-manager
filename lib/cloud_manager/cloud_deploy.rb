module VHelper::CloudManager
  class VHelperCloud
    def cluster_deploy(cluster_changes, vm_placement, options={})
      #TODO add placement code here

      thread_pool = nil
      @logger.debug("enter cluster_deploy")
      #thread_pool = ThreadPool.new(:max_threads => 32, :logger => @logger)
      @logger.debug("created thread pool")
      #Begin to parallel deploy vms
#      vm_deploy(thread_pool, cluster_changes) do |vm|
#        #TODO add change code here
#        @logger.info("changing vm #{vm.pretty_inspect}")
#        vm.status = VM_STATE_DONE
#        vm_finish(vm)
#      end
#      @logger.info("Finish all changes")
      vm_deploy(thread_pool, vm_placement) do |vm|
        @logger.info("placing vm aa#{vm.pretty_inspect}")
        vm_begin_create(vm)
        vm.status = VM_STATE_CLONE
        vm_clone(vm, :poweron => false)
        @logger.debug("finish clone")

        vm_poweroff(vm)

        vm.status = VM_STATE_RECONFIG
        vm_reconfigure_disk(vm)
        @logger.debug("finish reconfigure")

        vm.status = VM_STATE_POWER_ON
        vm_poweron(vm)
        @logger.debug("finish poweron")

        vm.status = VM_STATE_DONE
        vm_finish(vm)

        @logger.debug("finish")
      end
      @logger.info("Finish all deployments")
      "finished"
    end

    def vm_deploy(thread_pool, group_placement, options={})
      group_placement.each do |group|
        @logger.debug("enter groups: #{group.pretty_inspect}")
        #thread_pool.wrap do |pool|
          group.each do |vm|
            @logger.debug("enter : #{vm.pretty_inspect}")
         #   pool.process do
              begin
                yield(vm)
              rescue
                #TODO do some warning handler here
                raise
         #     end
            end
        #  end
        end
        @logger.info("##Finish change one vm_group")
      end
    end

    def vm_begin_create(vm, options={})
      add_deploying_vm(vm)
    end

    def vm_clone(vm, options={})
      @client.clone_vm(vm, options)
    end

    def vm_reconfigure_disk(vm, options={})
      vm.disks.each do |disk|
        @client.vm_create_disk(vm, disk)
      end
    end

    def vm_poweroff(vm, options={})
      @client.vm_power_off(vm)
    end

    def vm_poweron(vm, options={})
      @client.vm_power_on
    end

    def vm_finish(vm, options={})
      deploying_vm_move_to_existed(vm, options)
      #TODO
    end

    ###################################
    # inner used functions
    def gen_disk_name(datastore, vm, type, unit_number)
      return "[#{datastore.name}] #{vm.name}/#{type}-disk-#{unit_number}.vmdk"
    end

  end
end
