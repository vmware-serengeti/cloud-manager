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
    class Config
      def_const_value :client_connection, {'require' => 'plugin/client_fog', 'obj' => 'FogAdaptor'}
      def_const_value :template_placement , false

      def_const_value :debug_log_trace    , false
      def_const_value :debug_log_trace_depth , 3
      def_const_value :debug_log_obj2file , false
      def_const_value :debug_placement    , true
      def_const_value :debug_placement_rp , true
      def_const_value :debug_networking   , true
      def_const_value :debug_deploy       , true
      def_const_value :debug_waiting_ip   , true
      def_const_value :debug_placement_datastore, true
    end

    class Cloud
      attr_accessor :name
      attr_accessor :vc_req_resource_pools

      attr_accessor :status
      attr_accessor :clusters
      attr_accessor :vm_groups
      attr_accessor :vms
      attr_reader :input_cluster_info
      attr_reader :action

      attr_accessor :placement_failed
      attr_accessor :cloud_error_msg_que

      attr_reader :vc_share_datastore_pattern
      attr_reader :vc_local_datastore_pattern
      attr_reader :vc_req_datacenter
      attr_reader :vc_req_rps

      attr_reader :racks
      attr_reader :need_abort
      attr_reader :config

      attr_reader :client

      include Serengeti::CloudManager::Utils
      def initialize(cluster_info)
        @dc_resource = nil
        @clusters = nil
        @vm_lock = Mutex.new
        state_vms_init  #:existed,:deploy,:failed,:finished,:placed
        @need_abort = nil
        @cluster_name = cluster_info["name"]

        @status = CLUSTER_BIRTH
        @rs_lock = Mutex.new
        @client = nil
        @success = false
        @finished = false
        @placement_failed = 0
        @cluster_failed_num = 0
        @cloud_error_msg_que = []
      end

      def logger
        Serengeti::CloudManager.logger
      end

      def config
        Serengeti::CloudManager.config
      end

      def state_vms_init
        @state_vms = { 
          :existed  => { }, :deploy   => { },
          :failed   => { }, :finished => { },
          :placed   => { },
        }
      end

      def state_sub_vms_size(sub)
        @state_vms[sub].size
      end

      def state_sub_vms(sub)
        @state_vms[sub]
      end

      def set_cluster_error_msg(msg)
        @cloud_error_msg_que << msg
      end

      def mov_vm(vm, src, dest)
        @vm_lock.synchronize do
          raise "unknow type #{src} or #{dest}" if !@state_vms.key?(src) || !@state_vms.key?(dest)
          return if !@state_vms[src].has_key?(vm.name)
          # vm in this vms, move to des vms
          @state_vms[src].delete(vm.name)
          @state_vms[dest][vm.name] = vm
        end
      end

      def req_clusters_rp_to_hash(a)
        # resource_pool's name can be the same between different clusters
        Hash[a.map { |v| [v['name'], v['vc_rps']] } ]
      end

      def create_cloud_provider(cloud_provider)
        @cloud_provider = Config.new(cloud_provider)
        @name = cloud_provider["name"]
        raise "cloud provider name is nil!" if @cloud_provider.name.nil?
        raise "datacenter's name is nil!" if @cloud_provider.vc_datacenter.nil?
        raise "vc_clusters is nil" if @cloud_provider.vc_clusters.nil?
        @vc_req_rps = req_clusters_rp_to_hash(@cloud_provider.vc_clusters)
        logger.debug("req_rps:#{@vc_req_rps.pretty_inspect}")

        raise "cloud_provider's IP address is nil." if @cloud_provider.vc_addr.nil?

        @vc_share_datastore_pattern = change_wildcard2regex(@cloud_provider.vc_shared_datastore_pattern || [])
        @vc_local_datastore_pattern = change_wildcard2regex(@cloud_provider.vc_local_datastore_pattern || [])
        @racks = nil
      end

      def inspect
        "<Cloud: #{@name} status: #{@status} client: #{@client.inspect}>"
      end

      # Setting existed vm parameter from input
      def setting_existed_group_by_input(vm_groups_existed, vm_groups_input)
        #logger.debug("#{vm_groups_existed.class}")
        vm_groups_existed.each_value do |exist_group|
          #logger.debug("exist group: #{exist_group.pretty_inspect}")
          input_group = vm_groups_input[exist_group.name]
          next if input_group.nil?
          logger.debug("find same group #{exist_group.name}, and change each vm's configuration")
          exist_group.vm_ids.each_value { |vm| vm.ha_enable = input_group.req_info.ha }
        end
      end

      def update_input_group_by_existed(vm_groups_input, vm_groups_existed, cluster_data)
        # remove ips associated with existing vms from input ip pool
        vm_groups_existed.each_value do |exist_group|
          input_group = vm_groups_input[exist_group.name]
          next if input_group.nil?
          if cluster_data && cluster_data['group']
            cluster_data_instances = cluster_data['group'].select \
              { |group| group[instances] if group['name'] == exist_group.name}.first
            cluster_data_instances.each { |vm| input_group.network_res.ip_remove(0, vm['ip_address']) }
          end
          logger.debug("find same group #{exist_group.name}, and remove existed vm ip from input pool")
          exist_group.vm_ids.each_value { |vm| input_group.network_res.ip_remove(0, vm.ip_address) }
        end
      end

      def client_op(cloud, working)
        begin
          return yield
        rescue => e
          logger.error("#{working} failed.\n #{e} - #{e.backtrace.join("\n")}")
          set_cluster_error_msg("#{working} failed. Reason: #{e}")
          @cluster_failed_num += 1
          raise e
        end
      end

      def get_provider_info()
        info = {:provider => 'vsphere',
          :vsphere_server => @cloud_provider.vc_addr,
          :vsphere_username => @cloud_provider.vc_user,
          :vsphere_password => @cloud_provider.vc_pwd,
        }
#        logger.debug("login info:#{info.pretty_inspect}")
        info
      end

      def hosts
        @dc_resources.hosts
      end

      def get_clusters_name_within_input()
        info = @dc_resources.clusters.keys
#        logger.debug("clusters' name #{info.pretty_inspect}")
        info
      end

      def prepare_working(cluster_info, cluster_data)
        # Connect to Cloud server
        #@cluster_name = cluster_info["name"]
        logger.info("Connect to Cloud Server...")
        @input_cluster_info = cluster_info
        @status = CLUSTER_CONNECT

        @client = create_plugin_obj(config.client_connection, self)
        #client connect need more connect sessions
        client_op(self, 'vSphere login') { @client.login() }

        logger.debug("Create Resources ...")
        @resources = Resources.new(@client, self)

        # Create inputed vm_group from serengeti input
        logger.debug("Create vm group from input...")
        vm_groups_input = create_vm_group_from_serengeti_input(cluster_info, @cloud_provider.vc_datacenter)
        logger.obj2file(vm_groups_input, 'vm_groups_input')

        # Fetch Cluster information
        @status = CLUSTER_FETCH_INFO
        dc_resources = client_op(self, 'Fetch vSphere info') do
          @resources.fetch_datacenter(@cloud_provider.vc_datacenter, cluster_info['template_id'])
        end
        logger.obj2file(dc_resources, 'dc_resource-first')

        # Set template vm system disk size
        vm_sys_disk_size = nil
        dc_resources.vm_template.disks.each_value { |disk| break vm_sys_disk_size = disk.size if disk.unit_number == 0 }
        logger.debug("template vm disk size: #{@vm_sys_disk_size}")
        config.vm_sys_disk_size = vm_sys_disk_size
        
        # Create VM Group Info from resources
        logger.debug("Create vm group from resources...")
        vm_groups_existed = create_vm_group_from_resources(dc_resources, cluster_info["name"])
        logger.obj2file(vm_groups_existed, 'vm_groups_existed')

        setting_existed_group_by_input(vm_groups_existed, vm_groups_input)

        update_input_group_by_existed(vm_groups_input, vm_groups_existed, cluster_data)

        logger.info("Finish collect vm_group info from resources")
        {:dc_res => dc_resources, :group_existed => vm_groups_existed, :group_input => vm_groups_input}
      end

      def release_connection
        if !cloud_error_msg_que.empty?
          logger.debug("cloud manager have error/warning message. please chcek it, it is helpful for debugging")
          logger.debug("#{cloud_error_msg_que.pretty_inspect}")
        end
        return if @client.nil?
        @client.logout
        @client = nil
      end

      # Work for action process
      def action_process(act, task)
        result = nil
        begin
          logger.info("begin action:#{act}")
          Thread.current[:action] = act
          @action = act
          result = yield
          logger.info("finished action:#{act}")
          cluster_done(task)
          Thread.current[:action] = ''
        rescue => e
          logger.error("#{act} failed with #{e} #{e.backtrace.join("\n")}")
          set_cluster_error_msg("#{act} failed with #{e}")
          cluster_failed(task)
          Thread.current[:action] = ''
          return 'failed'
        end
        result
      end

      def change_wildcard2regex_str(str)
        str.gsub(/[*]/, '.*').gsub(/[?]/, '.{1}').tap { |out| return "^#{out}$" } unless str.nil?
        "^$"
      end

      def change_wildcard2regex(strArray)
        strArray.collect { |str| change_wildcard2regex_str(str) }
      end

    end
  end
end
