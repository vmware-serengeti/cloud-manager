module VHelper::VSphereCloud 
  STATE_RUNNING = "running"
  STATE_FAILED = "failed"
  STATE_SUCCESS = "success"

  CLUSTER_BIRTH = "birth"
  CLUSTER_CONNECT = "connectting"
  CLUSTER_FETCH_INFO = "fetching"
  CLUSTER_UPDATE = "updating"
  CLUSTER_PLACE = "placing"
  CLUSTER_DEPLOY = "deploying"
  CLUSTER_DELETE = "deleting"
  CLUSTER_DONE = "done"

  VM_STATE_BIRTH = "birth"
  VM_STATE_CLONE = "cloning"
  VM_STATE_RECONFIG = "reconfiging"
  VM_STATE_DELETE = "deleting"
  VM_STATE_DONE = "finished"

  VM_STATE_POWER_ON = "poweron..."
  VM_STATE_POWER_OFF = "poweroff..."
  SHARE = "share"
  LOCAL = "local"

  class Resource_info
    attr_accessor :cpu
    attr_accessor :mem
    attr_accessor :disk_type
    attr_accessor :disk_size
    attr_accessor :rack_id
    attr_accessor :vm_template
    attr_accessor :affinity
    def initialize(rp=nil)
      if rp
        @cpu = rp["cpu"] || 1
        @mem = rp["ram"] || 512
        # FIXME disks only use the first storage info
        @disk_size=  rp["storage"][0]["size"] || 0
        @disk_type = rp["storage"][0]["type"] || 0
        @affinity = rp["affinity"] || "none"
        @vm_template = rp["template"] || "none"
        @rack_id = nil
      end
    end
  end

  class VM_Group_Info
    attr_accessor :name
    attr_accessor :req_info  #class Resource_info
    attr_accessor :instances
    attr_accessor :vm_ids    #classes VM_Info
    def initialize(logger, rp=nil)
      @logger = logger
      @vm_ids = {}
      @req_info = Resource_info.new(rp)
      return unless rp
      @name = rp["name"] 
      @instances = rp["instance_num"]
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

  class Disk_Info
    attr_accessor :type
    attr_accessor :fullpath
    attr_accessor :size
    attr_accessor :unit_number
    attr_accessor :datastore
  end

  class VM_Info
    attr_accessor :name
    attr_accessor :status
    attr_accessor :host
    attr_accessor :disks
    attr_accessor :req_rp
    attr_accessor :vm_spec
    attr_accessor :vm_group
    attr_accessor :mob
    def initialize(vm_name, host, logger, req_rp = nil)
      @lock = Mutex.new
      @disks = {}
      @name = vm_name
      @host = host
      @req_rp = req_rp
      @vm_group = nil
      @status = VM_STATE_BIRTH 
    end

    def disk_add(size, fullpath, unit_number = 0)
      disk = Disk_Info.new
      disk.type = nil
      disk.fullpath = fullpath
      disk.size = size
      disk.unit_number = unit_number 
      disk.datastore = nil
      disks[fullpath] = disk
    end

    def delete_all_disk
      #seem no work to do
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
