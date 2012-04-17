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
          vm_finish(vm)
        }
      } 
      @logger.info("Finish all changes")

      vm_placement.each { |group|
        vm_group_by_threads(group) { |vm|
          vm.status = VM_STATE_CLONE
          next unless @existed_vms[vm.name].nil?
          vm_begin_create(vm)
          begin
            vm_clone(vm, :poweron => false)
          rescue => e
            @logger.debug("#{e}")
            #FIXME only handle duplicated issue.
            next
          end
          @logger.debug("#{vm.name} finish clone")

          vm.status = VM_STATE_RECONFIG
          vm_reconfigure_disk(vm)
          @logger.debug("#{vm.name} finish reconfigure")

          vm.status = VM_STATE_POWER_ON
          vm_poweron(vm)
          vm_finish(vm)
          @logger.debug("#{vm.name} finish poweron")
        }
      }

      @logger.debug("wait all existed vms' ip address")
      wait_thread = []
      vm_map_by_threads(@existed_vms) do |vm|
        while (vm.ip_address.nil? || vm.ip_address.empty?)
          @client.update_vm_properties_by_vm_mob(vm)
          @logger.debug("#{vm.name} ip: #{vm.ip_address}")
          sleep(4)
        end
        vm.status = VM_STATE_DONE
        @logger.debug("#{vm.name}: done")
      end

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
      thread_pool.wrap do |pool|
        group.each do |vm|
          @logger.debug("enter : #{vm.pretty_inspect}")
          pool.process do
            begin
              yield(vm)
            rescue
              #TODO do some warning handler here
              raise
            end
          end
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
      vm.disks.each_value do |disk|
        @client.vm_create_disk(vm, disk)
      end
    end

    def vm_poweroff(vm, options={})
      @client.vm_power_off(vm)
    end

    def vm_poweron(vm, options={})
      @client.vm_power_on(vm)
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
