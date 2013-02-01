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
    class Config
      def_const_value :client_connection, {'require' => 'plugin/client_fog', 'obj' => 'FogAdaptor'}
      def_const_value :template_placement , false

      def_const_value :debug_not_check_vm_mob, false
      def_const_value :debug_log_trace    , false
      def_const_value :debug_provider_login_info, false
      def_const_value :debug_log_trace_depth , 3
      def_const_value :debug_log_obj2file , false
      def_const_value :debug_placement    , true
      def_const_value :debug_placement_rp , true
      def_const_value :debug_networking   , true
      def_const_value :debug_deploy       , true
      def_const_value :debug_waiting_ip   , true
      def_const_value :debug_placement_datastore, true
      def_const_value :cloud_cluster_name, 'test'
      def_const_value :cloud_template_id, 'vm-0'
      def_const_value :cloud_cluster_share_datastore_pattern, []
      def_const_value :cloud_cluster_local_datastore_pattern, []
      def_const_value :cloud_rack_to_hosts, {}
      def_const_value :cloud_hosts_to_rack, {}
      def_const_value :cloud_existed_vms_mob, {}
      def_const_value :vc_local_datastore_pattern, []
      def_const_value :vc_share_datastore_pattern, []
      def_const_value :cloud_vhm_enable, false
      # if not specified, maintain the former setting, might be nil/unsigned Integer
      def_const_value :cloud_vhm_min_computenodes_num, nil
      def_const_value :cluster_has_local_datastores, false
     end

    class Cloud
      attr_accessor :name
      attr_accessor :vc_req_resource_pools

      attr_accessor :status
      attr_accessor :clusters
      attr_accessor :vm_groups
      attr_accessor :vms
      attr_reader :action

      attr_accessor :placement_failed
      attr_accessor :cloud_error_msg_que

      attr_reader :vc_req_rps

      attr_reader :racks
      attr_reader :need_abort
      #attr_reader :config

      attr_reader :client

      include Serengeti::CloudManager::Utils
      def initialize(task, options = {})
        @dc_resource = nil
        @clusters = nil
        @vm_lock = Mutex.new
        @task = task

        load_cloud_config_from_home
        @cluster_info       = options[:cluster_definition]
        @cloud_provider     = options[:cloud_provider]
        @cluster_last_data  = options[:cluster_data]
        @targets            = options[:targets]
        @racks              = @cluster_info['rack_topology']
        if !@racks.nil?
          hosts_rack = @racks
          rack_hosts  = {}
          hosts_rack.each do |k,v|
            logger.debug("k=#{k}, v=#{v}")
            if rack_hosts.key?(v)
              rack_hosts[v] << k
            else
              rack_hosts[v] = [k]
            end
          end
          config.cloud_rack_to_hosts = rack_hosts
          logger.debug("rack_to_hosts: #{rack_hosts.pretty_inspect}")
          config.cloud_hosts_to_rack = hosts_rack
          logger.debug("hosts_to_rack : #{hosts_rack.pretty_inspect}")
        end

        state_vms_init  #:existed,:deploy,:failed,:finished,:placed
        @need_abort = nil
        config.cloud_cluster_name = @cluster_info['name']
        config.cloud_template_id  = @cluster_info['template_id']
        config.cloud_vhm_enable = @cluster_info['automation_enable'] || false
        config.cloud_vhm_min_computenodes_num = @cluster_info['vhm_min_num']
        config.cluster_has_local_datastores = (!@cluster_info['vc_local_datastore_pattern'].nil?) and (!@cluster_info['vc_local_datastore_pattern'].empty?)

        @status = CLUSTER_BIRTH
        @client = nil
        @success = false
        @finished = false
        @placement_failed = 0
        @cluster_failed_num = 0
        @cloud_error_msg_que = []
        @existed_vm_mobs = {}
      end

      def load_cloud_config_from_home
        config_file = "#{Dir.home}/.cloud-manager.yaml"
        begin
          config = YAML.load(File.open(config_file))
          logger.debug("update config:#{config}") if !config.nil? and !config.empty?
          Serengeti::CloudManager.config.update(config)
        rescue => e
          logger.debug("Ignore ~/.cloud-manager.yaml configuration.")
        end
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

      def state_sub_vms_set_vm(sub, vm)
        @vm_lock.synchronize do
          state_sub_vms(sub)[vm.name] = vm
        end
      end

      def state_sub_vms(sub)
        @state_vms[sub]
      end

      def set_cluster_error_msg(msg)
        @cloud_error_msg_que << msg
      end

      def mov_vm(vm, src, dest)
        @vm_lock.synchronize do
          raise "Unknow VM state to move #{src} or #{dest}." if !@state_vms.key?(src) || !@state_vms.key?(dest)
          return if !@state_vms[src].has_key?(vm.name)
          # vm in this vms, move to des vms
          @state_vms[src].delete(vm.name)
          @state_vms[dest][vm.name] = vm
        end
      end

      def req_clusters_rp_to_hash(a)
        Hash[a.map { |v| [v['name'], v['vc_rps']] } ]
      end

      def create_cloud_provider(cloud_provider)
        @cloud_provider = Config.new(cloud_provider)
        @name = cloud_provider["name"]
        raise "Do not give cloud provider name!" if @cloud_provider.name.nil?
        raise "Do not give datacenter's name!" if @cloud_provider.vc_datacenter.nil?
        raise "Do not give vc_clusters' info." if @cloud_provider.vc_clusters.nil?
        @vc_req_rps = req_clusters_rp_to_hash(@cloud_provider.vc_clusters)
        logger.debug("req_rps:#{@vc_req_rps.pretty_inspect}")

        raise "Do not give cloud_provider's IP address." if @cloud_provider.vc_addr.nil?

        config.vc_share_datastore_pattern = change_wildcard2regex(@cloud_provider.vc_shared_datastore_pattern || [])
        config.vc_local_datastore_pattern = change_wildcard2regex(@cloud_provider.vc_local_datastore_pattern || [])
      end

      def inspect
        "<Cloud: #{@name} status: #{@status} client: #{@client.inspect}>"
      end

      # Setting existed vm parameter from input
      def setting_existed_group_by_input(vm_groups_existed, vm_groups_input, cluster_data)
        #logger.debug("#{vm_groups_existed.class}")
        vm_groups_existed.each_value do |exist_group|
          #logger.debug("exist group: #{exist_group.pretty_inspect}")
          input_group = vm_groups_input[exist_group.name]
          next if input_group.nil?
          logger.debug("find same group #{exist_group.name}, and change each vm's configuration")
          exist_group.vm_ids.each_value { |vm| vm.ha_enable = (input_group.req_info.ha == 'on') }
          exist_group.vm_ids.each_value { |vm|
            vm.ft_enable = (input_group.req_info.ha == 'ft')
            vm.ha_enable = vm.ft_enable if vm.ft_enable
          }
=begin
          if cluster_data && cluster_data['groups']
            cluster_data_instances = cluster_data['groups'].map do |group|
              group['instances'] if group['name'] == exist_group.name
            end
            cluster_data_instances = cluster_data_instances.flatten.compact

            cluster_data_instances.each do |vm|
              next if !exist_group.vm_ids.key?[vm['name']]
              exist_group.vm_ids[vm['name']].rack = cluster_data_instances[vm['name']]['rack']
            end
          end
=end
        end
      end

      def update_input_group_by_existed(vm_groups_input, vm_groups_existed, cluster_data)
        # remove ips associated with existing vms from input ip pool
        vm_groups_existed.each_value do |exist_group|
          input_group = vm_groups_input[exist_group.name]
          next if input_group.nil?
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
          :cert => @cloud_provider.cert,
          :key => @cloud_provider.key,
          :extension_key => @cloud_provider.extension_key,
          "log_level" => Serengeti::CloudManager.log_level
        }
        logger.debug("info: #{info.pretty_inspect}") if config.debug_provider_login_info
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

      def remove_shadow_vm(dc_res, vm_group_input)
        dc_res.clusters.each_value do |cluster|
          cluster.hosts.each_value do |host|
            host.vms.each_value do |vm|
              next if !vm_is_this_cluster?(vm.name)
              result = parse_vm_from_name(vm.name)
              next if !vm_group_input[result['group_name']]
              next if vm_group_input[result['group_name']].req_info.ha != 'ft'
              next if @client.is_vm_ft_primary(vm)
              logger.debug("#{vm.name} is not a ft primary vm.")
              host.vms.delete(vm.name)
            end
          end
        end
      end

      def create_existed_vm_mobs_from_cluster_data(cluster_data)
        return {} if cluster_data.nil? or cluster_data['groups'].nil?
        cluster_existed_vms = {}
        cluster_data['groups'].each do |group|
          group['instances'].each { |vm| cluster_existed_vms[vm['moid']] = vm['name'] }
        end
      cluster_existed_vms
      end

      def prepare_working(cluster_info, cluster_data)
        logger.debug("Create vm group from input...")
        vm_groups_input = create_vm_group_from_input(cluster_info, @cloud_provider.vc_datacenter)
        config.cloud_existed_vms_mob = create_existed_vm_mobs_from_cluster_data(cluster_data)
        logger.debug("existed vm mobs:#{config.cloud_existed_vms_mob.pretty_inspect}")
        logger.obj2file(vm_groups_input, 'vm_groups_input')

        if @client.nil?
          # Connect to Cloud server
          logger.info("Connect to Cloud Server...")
          @status = CLUSTER_CONNECT
          @client = create_plugin_obj(config.client_connection, self)
          client_op(self, 'vSphere login') { @client.login() }
        end

        # Fetch Cluster information
        logger.debug("Create Resources ...")
        resources = Resources.new(@client, self)

        @status = CLUSTER_FETCH_INFO

        dc_res = client_op(self, 'Fetch vSphere info') { resources.fetch_datacenter(@cloud_provider.vc_datacenter) }
        logger.obj2file(dc_res, 'dc_resource-first')

        # Set template vm system disk size
        vm_sys_disk_size = nil
        raise "Can not find template VM: [#{config.cloud_template_id}]." if dc_res.vm_template.nil?
        dc_res.vm_template.disks.each_value { |disk| break vm_sys_disk_size = disk.size if disk.unit_number == 0 }
        config.vm_sys_disk_size = vm_sys_disk_size

        # Create VM Group Info from resources
        logger.debug("Create vm group from resources...")
        remove_shadow_vm(dc_res, vm_groups_input)
        @vm_lock.synchronize do
          @state_vms[:existed] = {}
          @state_vms[:finished] = {}
        end
        vm_groups_existed = create_vm_group_from_resources(dc_res)
        logger.obj2file(vm_groups_existed, 'vm_groups_existed')

        setting_existed_group_by_input(vm_groups_existed, vm_groups_input, cluster_data)

        update_input_group_by_existed(vm_groups_input, vm_groups_existed, cluster_data)

        logger.info("Finish collect vm_group info from resources")
        {:dc_res => dc_res, :group_existed => vm_groups_existed, :group_input => vm_groups_input}
      end

      def release_connection
        if !@cloud_error_msg_que.empty?
          logger.debug("cloud manager have error/warning message. please chcek it, it is helpful for debugging")
          logger.debug("#{@cloud_error_msg_que.pretty_inspect}")
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
          set_cluster_error_msg("#{act} failed with: #{e}")
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
