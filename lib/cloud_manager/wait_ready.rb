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

    class Cloud
      TIMEOUT_WAIT_IP_TIME = 60*5
      SLEEP_WAIT_IP_TIME = 4
      def cluster_wait_ready(vm_pool)
        @logger.debug("wait all existed vms poweron and return their ip address")
        group_each_by_threads(vm_pool, :callee=>'wait vm ready') do |vm|
          begin
            @logger.debug("vm:#{vm.name} can ha?:#{vm.can_ha}, enable ? #{vm.ha_enable}")
            if !vm.ha_enable && vm.can_ha?
              next if !vm_deploy_op(vm, 'Disable HA') { @client.vm_set_ha(vm, vm.ha_enable)}
              @logger.debug("disable ha of vm #{vm.name}")
            elsif (!vm.can_ha? && vm.ha_enable)
              @logger.debug("vm:#{vm.name} can not enable ha on unHA cluster")
            end

            # Power On vm
            vm.status = VM_STATE_POWER_ON
            @logger.debug("vm:#{vm.name} power:#{vm.power_state}")
            if vm.power_state == 'poweredOff'
              next if !vm_deploy_op(vm, 'Power on') { @client.vm_power_on(vm)}
              @logger.debug("#{vm.name} has poweron")
            end

            # Wait IP
            vm.status = VM_STATE_WAIT_IP
            start_time = Time.now.to_i
            next if !vm_deploy_op(vm, 'Wait IP') do
              while (vm.ip_address.nil? || vm.ip_address.empty?)
                @client.update_vm_properties_by_vm_mob(vm)
                #FIXME check vm tools status
                wait_time = Time.now.to_i - start_time
                @logger.debug("vm:#{vm.name} wait #{wait_time}/#{TIMEOUT_WAIT_IP_TIME}s ip: #{vm.ip_address}")
                sleep(SLEEP_WAIT_IP_TIME)
                raise "#{vm.name} wait IP time out (#{wait_time}s, please check ip conflict. )" if (wait_time) > TIMEOUT_WAIT_IP_TIME
              end
            end

            vm.status = VM_STATE_DONE
            vm_finish(vm)
            @logger.debug("vm :#{vm.name} done")
          end
        end
        @logger.info("Finish all waiting")
        "finished"
      end
    end
  end
end

