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
      def_const_value :wait_ip_timeout_sec, 60*5
      def_const_value :wait_ip_sleep_sec  ,  4
      def_const_value :vm_data_disk_start_index,  2
    end

    class DiskInfo
      attr_accessor :type
      attr_accessor :fullpath
      attr_accessor :size
      attr_accessor :unit_number
      attr_accessor :datastore_name
      attr_accessor :shared
    end

    class VmInfo
      include Utils

      VM_STATE_BIRTH      = { :doing => "Initializing"  , :done => 'Not Exist' }
      VM_STATE_PLACE      = { :doing => "Initializing"  , :done => 'Not Exist' }
      VM_STATE_CLONE      = { :doing => "Cloning"       , :done => 'Created' }
      VM_STATE_RECONFIG   = { :doing => "Reconfiguring" , :done => 'Created' }
      VM_STATE_DELETE     = { :doing => "Deleting"      , :done => 'Deleted' }
      VM_STATE_DELETED    = { :doing => ""              , :done => 'Deleted' }
      VM_STATE_DONE       = { :doing => ""              , :done => 'Finished' }
      VM_STATE_FAIL       = { :doing => "Failure"       , :done => 'Failure' }
      VM_STATE_POWER_ON   = { :doing => "Powering On"   , :done => 'Powered On' }
      VM_STATE_WAIT_IP    = { :doing => "Waiting for IP", :done => 'VM Ready' }
      VM_STATE_READY      = { :doing => "Initializing"  , :done => 'VM Ready' }
      VM_STATE_POWER_OFF  = { :doing => "Powering Off"  , :done => 'Powered Off' }

      VM_ACTION_CREATE  = 'create'
      VM_ACTION_DELETE  = 'delete'
      VM_ACTION_UPDATE  = 'update'
      VM_ACTION_START   = 'startup'
      VM_ACTION_STOP    = 'stop'
      VM_ACTION_LIST    = 'list'

      VM_CREATE_PROCESS = {
        VM_STATE_BIRTH    => { :progress =>   0, :status => VM_STATE_BIRTH[:done] },
        VM_STATE_PLACE    => { :progress =>   2, :status => VM_STATE_BIRTH[:done] },
        VM_STATE_CLONE    => { :progress =>  10, :status => VM_STATE_PLACE[:done] },
        VM_STATE_RECONFIG => { :progress =>  60, :status => VM_STATE_CLONE[:done] },
        VM_STATE_READY    => { :progress =>  60, :status => VM_STATE_CLONE[:done] },
        VM_STATE_POWER_ON => { :progress =>  70, :status => VM_STATE_RECONFIG[:done] },
        VM_STATE_WAIT_IP  => { :progress =>  80, :status => VM_STATE_POWER_ON[:done] },
        VM_STATE_DONE     => { :progress => 100, :status => VM_STATE_WAIT_IP[:done] },
        VM_STATE_DELETED  => { :progress => 100, :status => VM_STATE_DELETE[:done] },
      }

      VM_DELETE_PROCESS = {
        VM_STATE_READY    => { :progress =>   0, :status => VM_STATE_READY[:done] },
        VM_STATE_DELETE   => { :progress =>  20, :status => VM_STATE_READY[:done] },
        VM_STATE_DONE     => { :progress => 100, :status => VM_STATE_DELETE[:done] },
      }

      VM_STOP_PROCESS = {
        VM_STATE_READY     => { :progress =>   0 , :status => VM_STATE_READY[:done] },
        VM_STATE_POWER_OFF => { :progress =>  20 , :status => VM_STATE_READY[:done] },
        VM_STATE_DONE      => { :progress => 100 , :status => VM_STATE_POWER_OFF[:done] },
      }

      VM_START_PROCESS = {
        VM_STATE_BIRTH    => { :progress =>   0, :status => VM_STATE_POWER_OFF[:done] },
        VM_STATE_READY    => { :progress =>  10, :status => VM_STATE_CLONE[:done] },
        VM_STATE_POWER_ON => { :progress =>  10, :status => VM_STATE_POWER_OFF[:done] },
        VM_STATE_WAIT_IP  => { :progress =>  50, :status => VM_STATE_POWER_ON[:done]  },
        VM_STATE_DONE     => { :progress => 100, :status => VM_STATE_WAIT_IP[:done]   },
      }

      VM_ACT_PROGRES = {
        VM_ACTION_CREATE  => VM_CREATE_PROCESS,
        VM_ACTION_DELETE  => VM_DELETE_PROCESS,
        VM_ACTION_START   => VM_START_PROCESS,
        VM_ACTION_STOP    => VM_STOP_PROCESS,
      }

      attr_accessor :id
      attr_accessor :name
      attr_accessor :status
      attr_accessor :host_name
      attr_accessor :host_mob
      attr_accessor :template_id

      attr_accessor :sys_datastore_moid #system disk's datastore
      attr_accessor :disks     #all allocated disk
      attr_accessor :req_rp    #wanted vm spec
      attr_accessor :vm_spec   #existed vm spec
      attr_accessor :vm_group  #link to vm_group
      attr_accessor :mob
      attr_accessor :resource_pool_moid

      attr_accessor :uuid
      attr_accessor :instance_uuid
      attr_accessor :power_state
      attr_accessor :error_msg
      attr_accessor :error_code
      attr_accessor :operatingsystem
      attr_accessor :hostname
      attr_accessor :connection_state
      attr_accessor :hypervisor
      attr_accessor :tools_state
      attr_accessor :tools_version
      attr_accessor :is_a_template
      attr_accessor :rp_cluster_name
      attr_accessor :rp_cluster_mob
      attr_accessor :group_name
      attr_accessor :created
      attr_accessor :cluster_name
      attr_accessor :rp_name
      attr_accessor :network_res
      attr_accessor :assign_ip
      attr_accessor :can_ha
      attr_accessor :ha_enable
      attr_accessor :ft_enable
      def succeed?;  ready?  end
      def finished?; succeed? || (@error_code.to_i != 0)  end
      attr_accessor :network_config_json

      attr_accessor :res_vms
      attr_accessor :storage_service
      attr_accessor :spec
      # for provisioning
      attr_accessor :created_at
      attr_accessor :availability_zone
      attr_accessor :tags
      attr_accessor :key_name
      attr_accessor :flavor_id
      attr_accessor :image_id
      attr_accessor :action

      def can_ha?; @can_ha;end
      def rack
        return nil if config.cloud_hosts_to_rack.empty?
        config.cloud_hosts_to_rack[@host_name]
      end

      def datastores
        data = {}
        ds = []
        @disks.each_value do |disk|
          if data.has_key?(disk.datastore_name)
            data[disk.datastore_name] += disk.size
          else
            data[disk.datastore_name] = disk.size
          end
        end
        data.each { |name, size| ds << { :name => name, :size => \
          (size+ResourceInfo::DISK_SIZE_UNIT_CONVERTER-1)/ResourceInfo::DISK_SIZE_UNIT_CONVERTER } }
        ds
      end

      def group_name
        return @group_name if @group_name
        result = parse_vm_from_name(@name)
        raise "VM name is not in the right format" if result.nil? or result.length != 3
        result["group_name"]
      end

      def inspect
        "Action:#{action} #{to_describe.pretty_inspect} "\
        "volumes:#{volumes.pretty_inspect} "\
        "disks:#{disks.pretty_inspect}"\
        "networking:#{network_config_json.pretty_inspect} "\
        "template_id:#{template_id.pretty_inspect}"\
        "req info:#{req_rp.pretty_inspect}"
      end

      def state; @power_state end
      def dns_name; @hostname end

      def ip_address
        (@power_state == "poweredOn" && !@deleted) ? @ip_address : ''
      end
      def public_ip_address; ip_address end
      def private_ip_address; ip_address end
      def ipaddress; ip_address end
      def ip_address=(ip)
        @ip_address = ip
      end

      def initialize(vm_name, cloud)
        @lock = Mutex.new
        @disks = {}
        @name = vm_name
        @vm_group = nil
        @status = VM_STATE_BIRTH
        @ip_address = ""
        @error_code = 0
        @error_msg = ""
        @assign_ip = []
        @network_cards = []
        @ha_enable = true
        @ft_enable = false
        @network_config_json = []
        @deleted = false
        @cloud = cloud
        @host_name = nil
        @res_vms = nil
        logger.debug("init vm: #{vm_name}")
      end

      include Serengeti::CloudManager::Utils

      # return value between [0..100]
      def get_progress
        progress = VM_ACT_PROGRES[@action]
        return 0 if progress.nil?
        step = progress[@status][:progress]
        return 0 if step.nil?
        step
      end

      # return service wanted values.
      def to_hash
        progress = VM_ACT_PROGRES[@action]
        attrs = {}
        attrs[:name]        = @name
        attrs[:hostname]    = @host_name
        attrs[:physical_host]= @host_name
        attrs[:ip_address]  = ip_address
        attrs[:status]      = progress ? progress[@status][:status] : ""
        attrs[:action]      = @status[:doing] #@status
        attrs[:moid]        = @mob

        attrs[:finished]    = ready? # FIXME should use 'vm.finished?'
        attrs[:succeed]     = ready? # FIXME should use 'vm.succeed?'
        attrs[:progress]    = get_progress

        attrs[:created]     = @deleted ? false : @created
        attrs[:deleted]     = @deleted
        attrs[:rack]        = rack

        attrs[:error_code]  = @error_code.to_i
        attrs[:error_msg]   = @error_msg.to_s
        attrs[:datastores]  = datastores
        attrs[:vc_cluster]  = {:name => @rp_cluster_name, :vc_rp => @rp_name}
        attrs[:ha]          = 'off'
        attrs[:ha]          = 'on' if @ha_enable
        attrs[:ha]          = 'ft' if @ft_enable
        attrs
      end

      # return some useful info for management
      def to_describe
        desc = to_hash
        desc[:host_mob]     = host_mob
        desc[:rp_mob]       = resource_pool_moid
        desc[:cluster_mob]  = rp_cluster_mob
        desc[:disks]        = Hash[disks.each_value.map {[]}]
        desc
      end

      # set vm's error message and print out warning message
      def set_error_msg(msg)
        @error_msg = "vm:#{name} #{msg}"
        logger.warn("#{msg}")
      end

      def assign_resources(spec, host, res_vms, service)
        @error_msg = nil

        @status = VmInfo::VM_STATE_PLACE
        @res_vms = res_vms
        @sys_datastore_moid = service['storage'].get_system_ds_moid(res_vms['storage'])
        logger.debug("vm: system moid #{sys_datastore_moid}")
        @resource_pool_moid = res_vms['resource_pool'].rp.mob
        @rp_cluster_name = res_vms['resource_pool'].rp.cluster.name
        @rp_name = res_vms['resource_pool'].rp.name
        logger.debug("vm: resource pool moid #{resource_pool_moid}")
        @spec = spec
        @host_name  = host.name
        @host_mob   = host.mob
        @storage_service = service['storage']

        logger.debug("ha: #{spec['ha']}")
        @ft_enable = (spec['ha'] == 'ft')
        @ha_enable = (spec['ha'] == 'on') || @ft_enable
        logger.debug("ft_enable: #{ft_enable}")

        @network_config_json = res_vms['network'].spec
        @network_res = res_vms['network'].network_res
        logger.debug("vm network json: #{network_config_json}")
        logger.debug("vm network port group: #{network_res.port_group(0)}")
      end

      def op_failed(src, e, working)
        logger.error("#{working} vm:#{name} failed.\n #{e} - #{e.backtrace.join("\n")}")
        @error_code = -1
        @error_msg = "#{working} vm:#{name} failed. #{e}"
        mov_vm(src, :failed)
      end

      def cloud_op(working, src = :existed)
        begin
          yield
          return 'OK'
        rescue PlacementException => e
          op_failed(src, e, working)
        rescue DeployException => e
          op_failed(src, e, working)
        rescue FetchException => e
          op_failed(src, e, working)
        rescue => e
          op_failed(src, e, working)
        end
        return nil
      end

      def client
        raise "Not assign cloud instance to vm:#{name}" if @cloud.nil?
        @cloud.client
      end

      def mov_vm(from, to)
        @cloud.mov_vm(self, from, to)
      end

      def fetch_vm_disks(vm_mob)
        disk_attrs = client.get_disks_by_vm_mob(vm_mob)
        disk_attrs.each do |attr|
          disk = disk_add(attr['size'], attr['path'], attr['scsi_num'])
          datastore_name = client.get_ds_name_by_path(attr['path'])
          disk.datastore_name = datastore_name
        end
      end


      # Create vm structure from cloud fetching
      def self.fetch_vm_from_cloud(vm_mob, cloud)
        vm_existed = nil
        begin
          # vm_mob may be stale, catch exception here
          vm_existed = cloud.client.ct_mob_ref_to_attr_hash(vm_mob, "VM")
        rescue => e
          return nil
        end

        return nil if block_given? and !yield(vm_existed)

        client = cloud.client
        vm = Serengeti::CloudManager::VmInfo.new(vm_existed["name"], cloud)

        #update vm info with properties
        client.update_vm_with_properties_string(vm, vm_existed)

        #update disk info
        vm.fetch_vm_disks(vm_mob)

        vm.can_ha = client.is_vm_in_ha_cluster(vm)
        vm.created = true
        vm
      end

      # deploy vm and config vm's networking, disk
      def deploy
        begin
          @action = VM_ACTION_CREATE
          @status = VM_STATE_CLONE
          mov_vm(:placed, :deploy)

          #logger.debug("vm's info :#{self.pretty_inspect}")
          return if !cloud_op('Clone', :deploy) { client.vm_clone(self, :poweron => false)}
          logger.info("vm:#{name} power:#{power_state} finish clone")

          #is this VM can do HA?
          @can_ha = client.is_vm_in_ha_cluster(self)

          @status = VM_STATE_RECONFIG
          return if !cloud_op('Reconfigure disk', :deploy) { reconfigure_disk}
          logger.info("vm:#{name} finish reconfigure disk")

          return if !cloud_op('Reconfigure network', :deploy) { reconfigure_network }
          logger.info("vm:#{name} finish reconfigure networking")

          #return if !cloud_op('Fetch Disk', :deploy) do
          #  vm_mob = client.get_vm_mob_ref_by_moid(mob, nil);
          #  fetch_vm_disks(vm_mob)
          #end
          #logger.info("vm:#{name} finish fetch disk info")
          #Move deployed vm to existed queue
          mov_vm(:deploy, :existed)
          @created = true
        ensure
          if error_code.to_i != 0
            # If occur error, It will delete this failed vm.
            client.vm_destroy(self)
            @status = VM_STATE_DELETED
            @deleted = true
          end
        end

      end

      # wait vm is ready
      def wait_ready(options = {})
        logger.debug("vm:#{name} can ha?:#{can_ha}, enable ? #{ha_enable}")
        if !ha_enable && can_ha?
          return if !cloud_op('Disable HA') { client.vm_set_ha(self, ha_enable) }
          logger.debug("disable ha of vm #{name}")
        elsif (!can_ha? && ha_enable)
          logger.debug("vm:#{name} can not enable ha on unHA cluster")
        end

        logger.debug("vm #{name} ft:#{ft_enable}")
        if ft_enable
          # Call enable FT interface
          #if power_state == 'poweredOn'
            #return if !cloud_op('Power Off') { client.vm_power_off(self) }
          #end
          return if !cloud_op('Operate FT') { client.vm_set_ft(self, ft_enable) }
          logger.debug("Enable FT on vm #{name}")
        end

        # Power On vm
        if options[:force_power_on]
          @status = VM_STATE_POWER_ON
          logger.debug("vm:#{name} power:#{power_state}")
          if power_state == 'poweredOff'
            return if !cloud_op('Power on') { client.vm_power_on(self) }
            logger.debug("#{name} has poweron")
            @power_state = "poweredOn"
          end
        end

        # Wait IP return
        if power_state == 'poweredOn'
          @status = VM_STATE_WAIT_IP
          start_time = Time.now.to_i
          return if !cloud_op('Wait IP') do
            logger.debug("Checking vm #{name} ip address #{@ip_address}.")
            client.get_vm_properties_by_vm_mob(self)
            while (ip_address.nil? || ip_address.empty?)
              client.get_vm_properties_by_vm_mob(self)
              #FIXME check vm tools status
              wait_time = Time.now.to_i - start_time
              logger.debug("vm:#{name} wait #{wait_time}/#{config.wait_ip_timeout_sec}s ip: #{ip_address}")
              sleep(config.wait_ip_sleep_sec)

              if (wait_time) > config.wait_ip_timeout_sec
                raise DeployException, "#{name} wait IP time out (#{wait_time}s, please check ip conflict. )"
              end
            end
          end
        end

        # VM is ready
        @status = VM_STATE_DONE
        mov_vm(:existed, :finished)
        logger.debug("vm :#{name} done")
      end

      # Stop VM in cloud
      def stop
        @action = VM_ACTION_STOP
        @status = VM_STATE_POWER_OFF

        logger.debug("stopping :#{name}")
        if power_state == 'poweredOn'
          return if !cloud_op('Stop') { client.vm_power_off(self) }
        end
        return if !cloud_op('Reread') { client.get_vm_properties_by_vm_mob(self) }
        @status = VM_STATE_DONE
        logger.debug("stop :#{name}")
        mov_vm(:existed, :finished)
      end

      # Delete VM in cloud
      def delete
        @action = VM_ACTION_DELETE
        @status = VM_STATE_DELETE
        #logger.debug("Can we delete #{name} same as #{cluster_info["name"]}?")
        logger.debug("delete vm : #{name}")
        if ft_enable
          return if !cloud_op('Delete') { client.vm_set_ft(self, false) }
        end
        return if !cloud_op('Delete') { client.vm_destroy(self) }
        @deleted = true
        @status = VM_STATE_DONE
        mov_vm(:existed, :finished)
      end

      def disk_add(size, fullpath, unit_number = 0)
        disk = DiskInfo.new
        disk.type = nil
        disk.fullpath = fullpath
        disk.size = size
        disk.unit_number = unit_number
        disk.datastore_name = nil
        @disks[fullpath] = disk
        disk
      end

      def reconfigure_disk(options={})
        res_vms['storage'].id = mob
        storage_service.deploy(res_vms['storage'])
        #disks.each_value { |disk| client.vm_create_disk(self, disk) if disk.unit_number > 0}
      end

      def reconfigure_network(options = {})
        client.vm_update_network(self, options) unless network_config_json.nil?
      end

      DISK_DEV_LABEL = "abcdefghijklmnopqrstuvwxyz"
      def delete_all_disk
        #seem no work to do
      end

      def wait_for(&block)
        instance_eval(&block)
      end

      def ready?
        @status == VM_STATE_DONE
      end

      def physical_host; @host_name; end

      def volumes(limitation = Serengeti::CloudManager.config.vm_data_disk_start_index)
        return res_vms['storage'].get_volumes_for_os('data') if !res_vms.nil?
        if !@disks.empty?
          return @disks.collect { |path, disk| "/dev/sd#{DISK_DEV_LABEL[disk.unit_number]}" \
            if disk.unit_number >= limitation }.compact.sort
        end
        []
      end
    end

  end
end
