module VHelper::CloudManager
  class VHelperCloud
    DEPLOY_GROUP_PARALLEL = "group_parallel"
    DEPLOY_GROUP_ORDER    = "group_order"
    DEPLOY_GROUP_POLICY   = [DEPLOY_GROUP_PARALLEL, DEPLOY_GROUP_ORDER]

    include VHelper::CloudManager::Parallel

    def cluster_deploy(cluster_changes, vm_placement, options={})
      policy = @input_cluster_info['deploy_policy'] || DEPLOY_GROUP_POLICY.first 
      policy.downcase!
      policy = DEPLOY_GROUP_POLICY.first if !DEPLOY_GROUP_POLICY.include?(policy)
      
      @logger.debug("enter cluster_deploy policy: #{policy}") 

      #thread_pool = ThreadPool.new(:max_threads => 32, :logger => @logger)
      @logger.debug("created thread pool")
      #Begin to parallel deploy vms
      cluster_changes.each { |group|
        group_each_by_threads(group, :callee=>'deploy changes', :order=>(policy==DEPLOY_GROUP_ORDER)) { |vm|
          #TODO add change code here
          @logger.info("changing vm #{vm.pretty_inspect}")
          vm.status = VM_STATE_DONE
        }
      }
      @logger.info("Finish all changes")

      group_each_by_threads(vm_placement, :order=>(policy==DEPLOY_GROUP_ORDER), :callee=>'deploy group') { |group|
          deploy_vm_group(group)
      }

      @logger.info("Finish all deployments")
      "finished"
    end

    def vm_deploy_op(vm, working)
      begin
        yield
      rescue => e
        @logger.debug("#{working} failed.")
        @logger.debug("#{e} - #{e.backtrace.join("\n")}")
        vm.error_code = -1
        vm.error_msg = "#{working} vm:#{vm.name} failed. #{e}"
        mov_vm(vm, @deploy_vms, @failure_vms)
        return nil
      end
      'OK'
    end

    def deploy_vm_group(group)
      group_each_by_threads(group, :callee=>'deploy vms') { |vm|
        # Existed VM is same as will be deployed?
        if (!vm.error_msg.nil?)
          @logger.debug("vm #{vm.name} can not deploy because:#{vm.error_msg}")
          next
        end
        vm.status = VM_STATE_CLONE
        mov_vm(vm, @preparing_vms, @deploy_vms)
        next if !vm_deploy_op(vm, 'Clone') { vm_clone(vm, :poweron => false)}
        @logger.debug("#{vm.name} power:#{vm.power_state} finish clone")

        vm.status = VM_STATE_RECONFIG
        next if !vm_deploy_op(vm, 'Reconfigure disk') { vm_reconfigure_disk(vm)}
        @logger.debug("#{vm.name} finish reconfigure disk")

        next if !vm_deploy_op(vm, 'Reconfigure network') {vm_reconfigure_network(vm)}
        @logger.debug("#{vm.name} finish reconfigure networking")

        #Move deployed vm to existed queue
        mov_vm(vm, @deploy_vms, @existed_vms)
        #TODO add reflush vm info
      }
    end

    def vm_clone(vm, options={})
      @client.clone_vm(vm, options)
    end

    def vm_reconfigure_disk(vm, options={})
      vm.disks.each_value { |disk| @client.vm_create_disk(vm, disk)}
    end

    def vm_reconfigure_network(vm, options = {})
      if (vm.network_res)
        vm.network_res.card_num.times {|card|
          @client.vm_update_network(vm, card)
        }
      end
    end

    def vm_poweroff(vm, options={})
      @client.vm_power_off(vm)
    end

    def vm_poweron(vm, options={})
      @client.vm_power_on(vm)
    end

    def vm_finish(vm, options={})
      mov_vm(vm, @existed_vms, @finished_vms)
    end

    ###################################
    # inner used functions
    def gen_disk_name(datastore, vm, type, unit_number)
      return "[#{datastore.name}] #{vm.name}/#{type}-disk-#{unit_number}.vmdk"
    end

  end
end
