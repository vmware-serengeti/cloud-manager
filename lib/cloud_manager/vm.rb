module Serengeti
  module CloudManager
    VM_STATE_BIRTH      = { :doing => "Initializing"  , :done => 'Not Exist' }
    VM_STATE_PLACE      = { :doing => "Initializing"  , :done => 'Not Exist' }
    VM_STATE_CLONE      = { :doing => "Cloning"       , :done => 'Created' }
    VM_STATE_RECONFIG   = { :doing => "Reconfiguring" , :done => 'Created' }
    VM_STATE_DELETE     = { :doing => "Deleting"      , :done => 'Deleted' }
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

    VM_CREATE_PROCESS = {
      VM_STATE_BIRTH    => { :progress =>   0, :status => VM_STATE_BIRTH[:done] },
      VM_STATE_PLACE    => { :progress =>   2, :status => VM_STATE_BIRTH[:done] },
      VM_STATE_CLONE    => { :progress =>  10, :status => VM_STATE_PLACE[:done] },
      VM_STATE_RECONFIG => { :progress =>  60, :status => VM_STATE_CLONE[:done] },
      VM_STATE_READY    => { :progress =>  60, :status => VM_STATE_CLONE[:done] },
      VM_STATE_POWER_ON => { :progress =>  70, :status => VM_STATE_RECONFIG[:done] },
      VM_STATE_WAIT_IP  => { :progress =>  80, :status => VM_STATE_POWER_ON[:done] },
      VM_STATE_DONE     => { :progress => 100, :status => VM_STATE_WAIT_IP[:done] },
      VM_STATE_DELETE   => { :progress => 100, :status => VM_STATE_DELETE[:done] },
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
      VM_STATE_READY    => { :progress =>  10, :status => VM_STATE_POWER_OFF[:done] },
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

    class VmInfo
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
      attr_accessor :ip_address
      attr_accessor :is_a_template
      attr_accessor :cluster_name
      attr_accessor :rp_cluster_name
      attr_accessor :group_name
      attr_accessor :created
      attr_accessor :rp_name
      attr_accessor :network_res
      attr_accessor :assign_ip
      attr_accessor :can_ha
      attr_accessor :ha_enable
      attr_accessor :deleted
      def succeed?;  ready?  end
      def finished?; succeed? || (@error_code.to_i != 0)  end
      attr_accessor :network_config_json

      # for provisioning
      attr_accessor :created_at
      attr_accessor :availability_zone
      attr_accessor :tags
      attr_accessor :key_name
      attr_accessor :flavor_id
      attr_accessor :image_id
      attr_accessor :action

      def can_ha?; @can_ha;end

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
        data.each { |k, v| ds << { :name => k, :size => v/ResourceInfo::DISK_SIZE_UNIT_CONVERTER } }
        ds
      end

      def inspect
        "#{to_hash.pretty_inspect} volumes:#{volumes.pretty_inspect} disks:#{disks.pretty_inspect}"\
        "networking:#{network_config_json.pretty_inspect}"
      end

      def state; @power_state end
      def dns_name; @hostname end
      def public_ip_address; @ip_address end
      def private_ip_address; @ip_address end
      def ipaddress; ip_address end

      def initialize(vm_name, req_rp = nil)
        @logger = Serengeti::CloudManager::Cloud.Logger
        @lock = Mutex.new
        @disks = {}
        @name = vm_name
        @req_rp = req_rp
        @vm_group = nil
        @status = VM_STATE_BIRTH
        @ip_address = ""
        @error_msg = ""
        @assign_ip = []
        @network_cards = []
        @ha_enable = true
        @network_config_json = []
        @deleted = false
      end

      def get_progress
        progress = VM_ACT_PROGRES[@action]
        return 0 if progress.nil?
        step = progress[@status][:progress]
        return 0 if step.nil?
        step
      end

      def to_hash
        progress = VM_ACT_PROGRES[@action]
        attrs = {}
        attrs[:name]        = @name
        attrs[:hostname]    = @host_name
        attrs[:ip_address]  = (@power_state == "poweredOn" && !deleted) ? @ip_address : nil
        attrs[:status]      = progress ? progress[@status][:status] : ""
        attrs[:action]      = @status[:doing] #@status

        attrs[:finished]    = ready? # FIXME should use 'vm.finished?'
        attrs[:succeed]     = ready? # FIXME should use 'vm.succeed?'
        attrs[:progress]    = get_progress

        attrs[:created]     = deleted ? false : @created
        attrs[:deleted]     = deleted

        attrs[:error_code]  = @error_code
        attrs[:error_msg]   = @error_msg
        attrs[:datastores]  = datastores
        attrs[:vc_cluster]  = {:name => @rp_cluster_name, :vc_rp => @rp_name}
        attrs[:ha]          = @ha_enable
        attrs
      end

      def disk_add(size, fullpath, unit_number = 0)
        disk = DiskInfo.new
        disk.type = nil
        disk.fullpath = fullpath
        disk.size = size
        disk.unit_number = unit_number
        disk.datastore_name = nil
        disks[fullpath] = disk
        disk
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

      def volumes(limitation = Serengeti::CloudManager::Cloud::VM_DATA_DISK_START_INDEX)
        @disks.collect { |path, disk| "/dev/sd#{DISK_DEV_LABEL[disk.unit_number]}" \
          if disk.unit_number >= limitation }.compact.sort
      end
    end

  end
end
