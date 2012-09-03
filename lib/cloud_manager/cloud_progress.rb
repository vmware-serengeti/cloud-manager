###############################################################################
#   Copyright (c) 2012 VMware, Inc. All Rights Reserved.
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

# @version 0.5.0

module Serengeti
  module CloudManager
    class Cloud
      CLOUD_WORK_CREATE = 'create'
      CLOUD_WORK_DELETE = 'delete'
      CLOUD_WORK_UPDATE = 'update'
      CLOUD_WORK_LIST   = 'list'
      CLOUD_WORK_START  = 'start'
      CLOUD_WORK_STOP   = 'stop'
      CLOUD_WORK_NONE   = 'none'

      CLUSTER_BIRTH       = "birth"
      CLUSTER_CONNECT     = "Connect to cloud"
      CLUSTER_FETCH_INFO  = "Fetching info from cloud"
      CLUSTER_UPDATE      = "Updating"
      CLUSTER_TEMPLATE_PLACE = "tempalte placing"
      CLUSTER_PLACE       = "Placing"
      CLUSTER_DEPLOY      = "Deploying"
      CLUSTER_RE_FETCH_INFO = "refetching"
      CLUSTER_WAIT_START  = "Waiting start"
      CLUSTER_DELETE    = "Deleting"
      CLUSTER_DONE      = 'Done'
      CLUSTER_START     = 'Starting'
      CLUSTER_STOP      = 'Stoping'

      CLUSTER_CREATE_PROCESS = {
        CLUSTER_BIRTH           => [0, 1],
        CLUSTER_CONNECT         => [1, 4],
        CLUSTER_FETCH_INFO      => [5, 5],
        CLUSTER_TEMPLATE_PLACE  => [10, 5],
        CLUSTER_PLACE           => [15, 5],
        CLUSTER_UPDATE          => [20, 5],
        CLUSTER_DEPLOY          => [25, 60],
        CLUSTER_RE_FETCH_INFO   => [25, 60],
        CLUSTER_WAIT_START      => [85, 20],
        CLUSTER_DONE            => [100, 0],
      }

      CLUSTER_DELETE_PROCESS = {
        CLUSTER_BIRTH       => [0, 1],
        CLUSTER_CONNECT     => [1, 4],
        CLUSTER_FETCH_INFO  => [5, 5],
        CLUSTER_DELETE      => [10, 90],
        CLUSTER_DONE        => [100, 0],
      }

      CLUSTER_LIST_PROCESS = {
        CLUSTER_BIRTH       => [0,  1],
        CLUSTER_CONNECT     => [1,  4],
        CLUSTER_FETCH_INFO  => [5, 95],
        CLUSTER_DONE        => [100, 0],
      }

      CLUSTER_START_PROCESS = {
        CLUSTER_BIRTH       => [0,  1],
        CLUSTER_CONNECT     => [1,  4],
        CLUSTER_FETCH_INFO  => [5,  25],
        CLUSTER_START       => [30, 70],
        CLUSTER_DONE        => [100, 0],
      }

      CLUSTER_STOP_PROCESS = {
        CLUSTER_BIRTH       => [0, 1],
        CLUSTER_CONNECT     => [1, 4],
        CLUSTER_FETCH_INFO  => [5, 25],
        CLUSTER_STOP        => [30, 70],
        CLUSTER_DONE        => [100, 0],
      }

      CLUSTER_PROCESS = {
        CLOUD_WORK_CREATE => CLUSTER_CREATE_PROCESS,
        CLOUD_WORK_DELETE => CLUSTER_DELETE_PROCESS,
        CLOUD_WORK_LIST   => CLUSTER_LIST_PROCESS,
        CLOUD_WORK_START  => CLUSTER_START_PROCESS,
        CLOUD_WORK_STOP   => CLUSTER_STOP_PROCESS,
      }

      # Get VMs' info from vm queues
      def get_result_by_vms(servers, vms_all, options={})
        vms_all.each_value do |vms|
          vms.each_value do |vm|
            result = parse_vm_from_name(vm.name)
            next if result.nil?
            vm.cluster_name = config.cloud_cluster_name #Serengeti cluster_name
            vm.group_name = result["group_name"]
            servers << vm
          end
        end
      end

      # Get cluster operation's status
      def get_result
        result = IaasResult.new
        @vm_lock.synchronize do
          result.waiting = state_sub_vms_size(:placed)
          result.deploy  = state_sub_vms_size(:deploy)
          result.waiting_start = state_sub_vms_size(:existed)
          result.success = state_sub_vms_size(:finished)
          result.failure = state_sub_vms_size(:failed) + @placement_failed + @cluster_failed_num
          result.succeed = @success && result.failure <= 0
          result.error_msg = (@cloud_error_msg_que.nil?) ? '' : @cloud_error_msg_que.join
          result.running = result.deploy + result.waiting + result.waiting_start
          result.total = result.running + result.success + result.failure
          result.servers = []
          get_result_by_vms(result.servers, @state_vms)
        end
        result
      end

      # Get cluster operation's progress
      def get_progress
        progress = IaasProcess.new
        progress.cluster_name = config.cloud_cluster_name
        progress.result = get_result
        progress.status = @status
        progress.finished = @finished
        progress.result.error_msg = "" if !@finished #Do not return error_msg, if not finished
        progress.progress = 0
        case @action
        when CLOUD_WORK_CREATE, CLOUD_WORK_DELETE, CLOUD_WORK_LIST, CLOUD_WORK_START, CLOUD_WORK_STOP
          prog = CLUSTER_PROCESS[@action]
          progress.progress = prog[@status][0]
          if (progress.result.total > 0)
            progress.progress = prog[@status][0] +
              prog[@status][1] * progress.result.servers.inject(0) \
              { |sum, vm| sum += vm.get_progress } / progress.result.total / 100
          end
        else
          progress.progress = 100
        end
        progress
      end

      def cluster_failed(task)
        logger.debug("Enter Cluster_failed")
        task.set_finish("failed")
        @success = false
        @finished = true
      end

      def cluster_done(task)
        logger.debug("Enter cluster_done")
        # TODO finish cluster information
        @status = CLUSTER_DONE
        task.set_finish("success")
        @success = true
        @finished = true
      end

    end
  end
end

