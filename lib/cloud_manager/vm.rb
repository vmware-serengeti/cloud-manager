module VHelper::CloudManager
  VM_STATE_BIRTH      = "birth"
  VM_STATE_CLONE      = "cloning"
  VM_STATE_RECONFIG   = "reconfiging"
  VM_STATE_DELETE     = "deleting"
  VM_STATE_DONE       = "finished"
  VM_STATE_FAIL       = "fails"
  VM_STATE_POWER_ON   = "poweron..."
  VM_STATE_WAIT_IP    = "waiting ip"
  VM_STATE_POWER_OFF  = "poweroff..."

  VM_ACTION_CREATE  = 'create'
  VM_ACTION_DELETE  = 'delete'
  VM_ACTION_UPDATE  = 'update'
  VM_ACTION_START   = 'startup'
  VM_ACTION_STOP    = 'stop'

  VM_CREATE_PROCESS = {
    VM_STATE_BIRTH    => 0,
    VM_STATE_CLONE    => 10,
    VM_STATE_RECONFIG => 60,
    VM_STATE_POWER_ON => 70,
    VM_STATE_WAIT_IP  => 80,
    VM_STATE_DONE     => 100,
  }

  VM_DELETE_PROCESS = {
    VM_STATE_BIRTH    => 0,
    VM_STATE_DELETE => 20,
    VM_STATE_DONE     => 100,
  }

  VM_STOP_PROCESS = {
    VM_STATE_BIRTH    => 0,
    VM_STATE_POWER_OFF=> 20,
    VM_STATE_DONE     => 100,
  }

  VM_START_PROCESS = {
    VM_STATE_BIRTH    => 0,
    VM_STATE_CLONE    => 10,
    VM_STATE_RECONFIG => 60,
    VM_STATE_POWER_ON => 70,
    VM_STATE_WAIT_IP  => 80,
    VM_STATE_DONE     => 100,
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
    def succeed?;  ready?  end
    def finished?; succeed? || !error_msg.to_s.empty? end
    
    # for provisioning
    attr_accessor :created_at
    attr_accessor :availability_zone
    attr_accessor :tags
    attr_accessor :key_name
    attr_accessor :flavor_id
    attr_accessor :image_id
    attr_accessor :action

    def can_ha?; @can_ha;end
    def get_error_msg
      return "OK" if @error_msg.to_s.empty?
      "ERR: #{error_msg}"
    end

    def datastores
      data = {}
      ds = []
      @disks.each_value { |disk|
        if data.has_key?(disk.datastore_name) 
          data[disk.datastore_name] += disk.size
        else
          data[disk.datastore_name] = disk.size
        end
      }
      data.each {|k, v| ds << {:name=>k, :size=>v/ResourceInfo::DISK_CHANGE_TIMES}}
      ds
    end

    def inspect
      "#{to_hash.pretty_inspect} #{get_error_msg}\n"
    end

    def state; @power_state end
    def dns_name; @hostname end
    def public_ip_address; @ip_address end
    def private_ip_address; @ip_address end
    def ipaddress; ip_address end

    def initialize(vm_name, logger, req_rp = nil)
      @lock = Mutex.new
      @disks = {}
      @name = vm_name
      @req_rp = req_rp
      @vm_group = nil
      @status = VM_STATE_BIRTH
      @ip_address = ""
      @error_msg = ""
      @assign_ip = []
      @networking = nil
    end

    def get_create_progress
      VM_CREATE_PROCESS[@status] || 0
    end

    def to_hash
      attrs = {}
      attrs[:name] = @name
      attrs[:hostname] = @hostname
      attrs[:ip_address] = nil
      attrs[:ip_address] = @ip_address if @power_state == "poweredOn"
      attrs[:status] = @status

      attrs[:finished] = ready? # FIXME should use 'vm.finished?'
      attrs[:succeed] = ready? # FIXME should use 'vm.succeed?'
      attrs[:progress] = get_create_progress

      attrs[:created] = @created
      attrs[:deleted] = false

      attrs[:error_code] = @error_code
      attrs[:error_msg] = @error_msg
      attrs[:datastores] = datastores
      attrs[:vc_cluster] = {:name=>@rp_cluster_name, :vc_rp=>@rp_name}
      attrs[:ha] = @ha_enable
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

    def delete_all_disk
      #seem no work to do
    end

    def wait_for(&block)
      instance_eval(&block)
    end

    def ready?
      @status == VM_STATE_DONE 
    end
  end

end
