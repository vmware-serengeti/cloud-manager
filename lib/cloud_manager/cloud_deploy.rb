module VHelper::CloudManager
  class VHelperCloud
    def cluster_deploy(cluster_changes, vm_placement, options={})
      #TODO add placement code here

      thread_pool = nil
      @logger.debug("enter cluster_deploy")
      #thread_pool = ThreadPool.new(:max_threads => 32, :logger => @logger)
      @logger.debug("created thread pool")
      #Begin to parallel deploy vms
      cluster_changes.each { |group|
        vm_group_by_threads(group) { |vm|
          #TODO add change code here
          @logger.info("changing vm #{vm.pretty_inspect}")
          vm.status = VM_STATE_DONE
          vm_finish_deploy(vm)
        }
      }
      @logger.info("Finish all changes")

      vm_placement.each { |group|
        vm_group_by_threads(group) { |vm|
          next unless @existed_vms[vm.name].nil?
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
            @logger.debug("#{e} - #{e.backtrace.join("\n")}")
            #FIXME only handle duplicated issue.
            next
          end
          @logger.debug("#{vm.name} finish clone")

          vm.status = VM_STATE_RECONFIG
          vm_reconfigure_disk(vm)
          @logger.debug("#{vm.name} finish reconfigure")

          vm.status = VM_STATE_POWER_ON
          vm_poweron(vm)
          vm_finish_deploy(vm)
          @logger.debug("#{vm.name} finish poweron")
        }
      }

      @logger.debug("wait all existed vms' ip address")
      wait_thread = []
      @status = CLUSTER_WAIT_START
      vm_map_by_threads(@existed_vms) { |vm|
        while (vm.ip_address.nil? || vm.ip_address.empty?)
          @client.update_vm_properties_by_vm_mob(vm)
          @logger.debug("#{vm.name} ip: #{vm.ip_address}")
          sleep(4)
        end
        vm.status = VM_STATE_DONE
        vm_finish(vm)
        @logger.debug("#{vm.name}: done")
      }

      @logger.info("Finish all deployments")
      "finished"
    end

    def vm_map_by_threads(map, options={})
      work_thread = []
      map.each_value do |vm|
        work_thread << Thread.new(vm) { |vm| yield vm }
      end
      work_thread.each { |t| t.join }
      @logger.info("##Finish change one vm_group")
    end

    def vm_group_by_threads(group, options={})
      work_thread = []
      group.each do |vm|
        work_thread << Thread.new(vm) { |vm| yield vm }
      end
      work_thread.each { |t| t.join }
      @logger.info("##Finish change one vm_group")
    end

    def vm_deploy_group_pool(thread_pool, group, options={})
      thread_pool.wrap { |pool|
        group.each { |vm|
          @logger.debug("enter : #{vm.pretty_inspect}")
          pool.process {
            begin
              yield(vm)
            rescue
              #TODO do some warning handler here
              raise
            end
          }
        @logger.info("##Finish change one vm_group")
        }
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
