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
        group_each_by_threads(group, :callee=>'deploy changes') { |vm|
          #TODO add change code here
          @logger.info("changing vm #{vm.pretty_inspect}")
          vm.status = VM_STATE_DONE
          vm_finish_deploy(vm)
        }
      }
      @logger.info("Finish all changes")

      group_each_by_threads(vm_placement, :order=>(policy==DEPLOY_GROUP_ORDER)) { |group|
          deploy_vm_group(group)
      }

      @logger.debug("wait all existed vms poweron and return their ip address")
      wait_thread = []
      @status = CLUSTER_WAIT_START
      map_each_by_threads(@existed_vms) { |vm|
        # Power On vm
        vm.status = VM_STATE_POWER_ON
        @logger.debug("vm:#{vm.name} power:#{vm.power_state}")
        if vm.power_state == 'poweredOff'
          vm_poweron(vm)
          @logger.debug("#{vm.name} has poweron")
        end
        vm.status = VM_STATE_WAIT_IP
        while (vm.ip_address.nil? || vm.ip_address.empty?)
          @client.update_vm_properties_by_vm_mob(vm)
          @logger.debug("#{vm.name} ip: #{vm.ip_address}")
          sleep(4)
        end
        #TODO add ping progress to tested target vm is working
        vm.status = VM_STATE_DONE
        vm_finish(vm)
        @logger.debug("#{vm.name}: done")
      }

      @logger.info("Finish all deployments")
      "finished"
    end

    def deploy_vm_group(group)
      group_each_by_threads(group, :callee=>'deploy vms') { |vm|
        # Existed VM is same as will be deployed?
        if (!vm.error_msg.nil?)
          @logger.debug("vm #{vm.name} can not deploy because:#{vm.error_msg}")
          next
        end
        vm.status = VM_STATE_CLONE
        vm_begin_create(vm)
        begin
          vm_clone(vm, :poweron => false)
        rescue => e
          @logger.debug("clone failed")
          vm.error_code = -1
          vm.error_msg = "Clone vm:#{vm.name} failed. #{e}"
          #FIXME only handle duplicated issue.
          next
        end
        @logger.debug("#{vm.name} power:#{vm.power_state} finish clone")

        vm.status = VM_STATE_RECONFIG
        vm_reconfigure_disk(vm)
        @logger.debug("#{vm.name} finish reconfigure disk")
        vm_reconfigure_network(vm)
        @logger.debug("#{vm.name} finish reconfigure networking")

        #Move deployed vm to existed queue
        vm_finish_deploy(vm)
        #TODO add reflush vm info
      }
    end

    def vm_begin_create(vm, options={})
      @logger.debug("move prepare to deploy :#{vm.name}")
      add_deploying_vm(vm)
    end

    def vm_clone(vm, options={})
      @logger.debug("cpu:#{vm.req_rp.cpu} mem:#{vm.req_rp.mem}")
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

    def vm_finish_deploy(vm, options={})
      deploying_vm_move_to_existed(vm, options)
    end

    def vm_finish(vm, options={})
      existed_vm_move_to_finish(vm, options)
    end

    ###################################
    # inner used functions
    def gen_disk_name(datastore, vm, type, unit_number)
      return "[#{datastore.name}] #{vm.name}/#{type}-disk-#{unit_number}.vmdk"
    end

  end
end
