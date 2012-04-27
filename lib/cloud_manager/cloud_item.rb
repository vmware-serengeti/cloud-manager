module VHelper::CloudManager
  STATE_RUNNING = "running"
  STATE_FAILED = "failed"
  STATE_SUCCESS = "success"

  VM_STATE_BIRTH = "birth"
  VM_STATE_CLONE = "cloning"
  VM_STATE_RECONFIG = "reconfiging"
  VM_STATE_DELETE = "deleting"
  VM_STATE_DONE = "finished"
  VM_STATE_FAIL = "fails"
  VM_STATE_POWER_ON = "poweron..."
  VM_STATE_WAIT_IP  = "waiting ip"
  VM_STATE_POWER_OFF = "poweroff..."

  VM_CREATE_PROCESS = {
    VM_STATE_BIRTH    => 0,
    VM_STATE_CLONE    => 10,
    VM_STATE_RECONFIG => 60,
    VM_STATE_POWER_ON => 70,
    VM_STATE_WAIT_IP  => 80,
    VM_STATE_DONE     => 100,
  }

  SHARE = "share"
  LOCAL = "local"

  class ResourceInfo
    DISK_CHANGE_TIMES = 1024
    attr_accessor :cpu
    attr_accessor :mem
    attr_accessor :disk_type
    attr_accessor :disk_size
    attr_accessor :disk_pattern
    attr_accessor :rack_id
    attr_accessor :template_id
    attr_accessor :affinity
    def initialize(rp=nil, template_id=nil)
      if rp
        @cpu = rp["cpu"] || 1
        @mem = rp["memory"] || 512
        # FIXME disks only use the first storage info
        @disk_size =  rp["storage"]["size"] || 0
        @disk_pattern = rp["storage"]["name_pattern"] 
        @disk_size *= DISK_CHANGE_TIMES
        @disk_type = rp["storage"]["type"] 
        @disk_type = 'shared' if @disk_type != 'local'
        @affinity = rp["affinity"] || "none"
        @template_id = rp["template_id"] || template_id
        @rack_id = nil
      end
    end
  end

  class VmGroupInfo
    attr_accessor :name
    attr_accessor :req_info  #class ResourceInfo
    attr_reader   :vc_req
    attr_accessor :instances
    attr_accessor :req_rps
    attr_accessor :vm_ids    #classes VmInfo
    def initialize(logger, rp=nil, template_id=nil)
      @logger = logger
      @vm_ids = {}
      @req_info = ResourceInfo.new(rp, template_id)
      return unless rp
      @name = rp["name"]
      @instances = rp["instance_num"]
      @req_rps = {}
    end

    def size
      vm_ids.size
    end

    def del_vm(vm_mob)
      vm_info = find_vm(vm_mob)
      return nil unless vm_info
      vm_info.delete_all_disk

      @vm_ids.delete(vm_mob)
    end
    def add_vm(vm_info)
      if @vm_ids[vm_info.mob].nil?
        @vm_ids[vm_info.mob] = vm_info
      else
        @logger.debug("#{vm_info.name} is existed.")
      end
    end
    def find_vm(vm_mob)
      @vm_ids[vm_mob]
    end
  end

  class DiskInfo
    attr_accessor :type
    attr_accessor :fullpath
    attr_accessor :size
    attr_accessor :unit_number
    attr_accessor :datastore_name
  end

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
    attr_accessor :group_name
    attr_accessor :created
    attr_accessor :rp_name
    def succeed?;  ready?  end
    def finished?; succeed? || !error_msg.to_s.empty? end
    
    # for provisioning
    attr_accessor :created_at
    attr_accessor :availability_zone
    attr_accessor :tags
    attr_accessor :key_name
    attr_accessor :flavor_id
    attr_accessor :image_id

    def get_error_msg
      return "OK" if @error_msg.nil?
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
      data.each {|k, v| ds << {:name=>k, :size=>v/DISK_CHANGE_TIMES}}
      ds
    end

    def inspect
      "name:#{@name} host:#{@hostname} ip:#{@ip_address} status:#{@status} created:#{@created} state:#{@power_state} #{get_error_msg}\n"
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
    end

    def get_create_progress
      VM_CREATE_PROCESS[@status] || 0
    end

    def to_hash
      attrs = {}
      attrs[:hostname] = @hostname
      attrs[:ip_address] = @ip_address
      attrs[:status] = @status

      attrs[:finished] = ready? # FIXME should use 'vm.finished?'
      attrs[:succeed] = ready? # FIXME should use 'vm.succeed?'
      attrs[:progress] = get_create_progress

      attrs[:created] = @created
      attrs[:deleted] = false

      attrs[:error_code] = vm.error_code
      attrs[:error_msg] = vm.error_msg
      attrs[:datastores] = datastores
      attrs[:vc_clusters] = {:name=>@cluster_name, :vc_rp=>@rp_name}
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
