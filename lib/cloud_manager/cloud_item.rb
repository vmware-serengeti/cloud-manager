module VHelper::CloudManager
  STATE_RUNNING = "running"
  STATE_FAILED = "failed"
  STATE_SUCCESS = "success"

  CLUSTER_BIRTH = "birth"
  CLUSTER_CONNECT = "connectting"
  CLUSTER_FETCH_INFO = "fetching"
  CLUSTER_UPDATE = "updating"
  CLUSTER_PLACE = "placing"
  CLUSTER_DEPLOY = "deploying"
  CLUSTER_WAIT_START = "waiting start"
  CLUSTER_DELETE = "deleting"
  CLUSTER_DONE = "done"

  VM_STATE_BIRTH = "birth"
  VM_STATE_CLONE = "cloning"
  VM_STATE_RECONFIG = "reconfiging"
  VM_STATE_DELETE = "deleting"
  VM_STATE_DONE = "finished"
  VM_STATE_FAIL = "fails"

  VM_STATE_POWER_ON = "poweron..."
  VM_STATE_POWER_OFF = "poweroff..."
  SHARE = "share"
  LOCAL = "local"

  class ResourceInfo
    DISK_CHANGE_TIMES = 1024
    attr_accessor :cpu
    attr_accessor :mem
    attr_accessor :disk_type
    attr_accessor :disk_size
    attr_accessor :rack_id
    attr_accessor :template_id
    attr_accessor :affinity
    def initialize(rp=nil, template_id=nil)
      if rp
        @cpu = rp["cpu"] || 1
        @mem = rp["memory"] || 512
        # FIXME disks only use the first storage info
        @disk_size =  rp["storage"]["size"] || 0
        @disk_size *= DISK_CHANGE_TIMES
        @disk_type = rp["storage"]["type"] 
        @disk_type = 'shared' if @disk_type != 'local'
        @affinity = rp["affinity"] || "none"
        @template_id = template_id
        @template_id = rp["template_id"]if rp["template_id"]
        @rack_id = nil
      end
    end
  end

  class VmGroupInfo
    attr_accessor :name
    attr_accessor :req_info  #class ResourceInfo
    attr_accessor :instances
    attr_accessor :vm_ids    #classes VmInfo
    def initialize(logger, rp=nil, template_id=nil)
      @logger = logger
      @vm_ids = {}
      @req_info = ResourceInfo.new(rp, template_id)
      return unless rp
      @name = rp["name"]
      @instances = rp["instance_num"]
    end

    def ready?
      @status == VM_STATE_DONE 
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
    attr_accessor :vm_group   #link to vm_group
    attr_accessor :mob
    attr_accessor :resource_pool_moid

    attr_accessor :uuid
    attr_accessor :instance_uuid
    attr_accessor :power_state
    attr_accessor :error_msg
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
    
    # for provisioning
    attr_accessor :created_at
    attr_accessor :availability_zone
    attr_accessor :tags
    attr_accessor :key_name
    attr_accessor :flavor_id
    attr_accessor :image_id

    def inspect
      "name:#{@name} host:#{@hostname} ip:#{@ip_address} created:#{@created} state:#{@power_state} err:#{@error_msg}\n"
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
      !! ip_address
    end

  end

  class VHelperCloud
    attr_accessor :name
    attr_accessor :vc_req_resource_pools
    attr_accessor :vc_req_datacenter
    attr_accessor :vc_req_clusters
    attr_accessor :vc_address
    attr_accessor :vc_username
    attr_accessor :vc_password
    attr_accessor :vc_share_store_patten
    attr_accessor :vc_local_store_patten

    attr_accessor :status
    attr_accessor :clusters
    attr_accessor :vm_groups
    attr_accessor :vms

  end

end
