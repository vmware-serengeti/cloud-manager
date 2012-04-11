require './cloud_item'
require './utils'
module VHelper::CloudManager
  class VHelperCloud
    def cluster_deploy(cluster_changes, vm_placement, options={})
      #TODO add placement code here

      thread_pool = ThreadPool.new(:max_threads => 32)
      #Begin to parallel deploy vms
      vm_deploy(thread_pool, cluster_changes) do |vm|
        #TODO add change code here
        @logger.info("changing vm #{vm.name}")
        vm.status = VM_STATE_DONE
        vm_finish(vm)
      end
      @logger.info("Finish all changes")

      vm_deploy(thread_pool, vm_placement) do |vm|
        @logger.info("placing vm #{vm.name}")
        vm_begin_create(vm)
        vm.status = VM_STATE_CLONE
        vm_clone(vm, :poweron => false)

        vm.status = VM_STATE_RECONFIG
        reconfigure_vm_disk(vm)

        vm.status = VM_STATE_POWER_ON
        vm_poweron(vm)

        vm.status = VM_STATE_DONE
        vm_finish(vm)
      end
      @logger.info("Finish all deployments")
    end

    def vm_deploy(thread_pool, group_placement, options={})
      group_placement.each do |group_change|
        thread_pool.wrap do |pool|
          group_placement.each do |vm|
            pool.process do
              begin
                yield vm
              rescue
                #TODO do some warning handler here
              end
            end
          end
        end
        @logger.inf("##Finish change one vm_group")
      end
    end

    def vm_begin_create(vm, options={})
      add_deploying_vm(vm)
    end

    def vm_clone(vm, options={})
      #TODO
    end

    def vm_reconfigure_disk(vm, options={})
      #TODO
    end

    def vm_poweron(vm, options={})
      #TODO
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
