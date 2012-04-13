module VHelper::CloudManager
  class Resources
    class Datacenter
      attr_accessor :mob
      attr_accessor :name
      attr_accessor :clusters
      attr_accessor :racks
      attr_accessor :share_datastore_pattern
      attr_accessor :local_datastore_pattern
      attr_accessor :allow_mixed_datastores
      attr_accessor :spec
      def inspect
        "<Datacenter: #{@mob} / #{@name}>"
      end
    end

    class Datastore
      attr_accessor :mob
      attr_accessor :name
      attr_accessor :type
      attr_accessor :total_space
      attr_accessor :free_space
      attr_accessor :unaccounted_space

      def real_free_space
        @free_space - @unaccounted_space
      end

      def inspect
        "<Datastore: #{@mob} / #{@name}>"
      end
    end

    class Cluster
      attr_accessor :mob
      attr_accessor :name
      attr_accessor :datacenter
      attr_accessor :resource_pool_moid
      attr_accessor :hosts
      attr_accessor :share_datastores
      attr_accessor :local_datastores
      attr_accessor :idle_cpu
      attr_accessor :total_memory
      attr_accessor :free_memory
      attr_accessor :unaccounted_memory
      attr_accessor :mem_over_commit
      attr_accessor :vms

      def real_free_memory
        @free_memory - @unaccounted_memory * @mem_over_commit
      end

      def inspect
        "<Cluster: #{@mob} / #{@name}>"
      end
    end

    class ResourcePool
      attr_accessor :mob
      attr_accessor :name
      attr_accessor :total_memory       #MB
      attr_accessor :free_memory
      attr_accessor :unaccounted_memory
      def real_free_memory
        @free_memory - @unaccounted_memory * @mem_over_commit
      end
      def inspect
        "<Host: #{@mob} / #{@name}, #{@real_free_memory}>"
      end
    end

    class Host
      attr_accessor :mob
      attr_accessor :name

      attr_accessor :datacenter         # this host belongs to which datacenter
      attr_accessor :cluster            # this host belongs to which cluster
      attr_accessor :resource_pool      # this host belongs to which resource_pool
      attr_accessor :rack_name          # rack name
      attr_accessor :share_datastores
      attr_accessor :local_datastores
      attr_accessor :cpu_limit          #MHZ
      attr_accessor :idle_cpu           # %
      attr_accessor :total_memory       #MB
      attr_accessor :free_memory
      attr_accessor :unaccounted_memory
      attr_accessor :mem_over_commit
      attr_accessor :datastores         #
      attr_accessor :vms                # all vms belongs to this host

      def real_free_memory
        @free_memory - @unaccounted_memory * @mem_over_commit
      end

      def inspect
        "<Host: #{@mob} / #{@name}, #{@share_datastores}, #{@local_datastores}, #{@real_free_memory}>, vm #{@vms.size}"
      end
    end

    #########################################################
    # Begin Resource functions
    def initialize(client, vhelper, mem_over_commit = 1.0)
      @client           = client
      @vhelper          = vhelper
      @datacenter       = {}
      @lock             = Mutex.new
      @logger           = client.logger
      @mem_over_commit  = mem_over_commit
    end

    def fetch_datacenter()
      datacenter_name = @vhelper.vc_req_datacenter
      datacenter_mob = @client.get_dc_mob_ref_by_path(datacenter_name)
      return nil if datacenter_mob.nil?
      attr = @client.ct_mob_ref_to_attr_hash(datacenter_mob, "DC")

      datacenter                      = Datacenter.new
      datacenter.mob                  = attr[:mo_ref]
      datacenter.name                 = datacenter_name

      @logger.debug("Found datacenter: #{datacenter.name} @ #{datacenter.mob}")

      raise "Missing share_datastore_pattern in director config" if @vhelper.vc_share_datastore_patten.nil?
      datacenter.share_datastore_pattern    = Regexp.new(@vhelper.vc_share_datastore_patten)

      local_regex = @vhelper.vc_local_datastore_patten
      local_regex = "" if local_regex.nil?
      @logger.debug("Local Regex: #{local_regex}")

      datacenter.local_datastore_pattern = Regexp.new(local_regex)

      datacenter.allow_mixed_datastores = @vhelper.allow_mixed_datastores

      datacenter.racks = @vhelper.racks

      datacenter.clusters = fetch_clusters(datacenter, datacenter_mob)
      datacenter
    end

    def fetch_clusters(datacenter, datacenter_mob)
      cluster_mobs = @client.get_clusters_by_dc_mob(datacenter_mob)

      cluster_names = @vhelper.vc_req_clusters[0]["name"]

      clusters = {}
      @logger.debug("#{cluster_mobs.pretty_inspect}")
      cluster_mobs.each do |cluster_mob|
        @logger.debug("cluster mob:#{cluster_mob}")
        requested_resource_pool = @vhelper.vc_req_clusters[0]["vc_rps"][0]
        cluster_resource_pool_attr = fetch_resource_pool(cluster_mob, requested_resource_pool)

        next if cluster_resource_pool_attr.nil?

        attr = @client.ct_mob_ref_to_attr_hash(cluster_mob, "CS")
        # chose cluster in cluster_names
        next unless cluster_names.include?(attr["name"])

        cluster                    = Cluster.new
        cluster.mem_over_commit    = @mem_over_commit
        cluster.mob                = attr["mo_ref"]
        cluster.name               = attr["name"]
        cluster.vms                = {}

        #@logger.debug("Found cluster: #{cluster.name} @ #{cluster.mob}")

        cluster.resource_pool_moid    = cluster_resource_pool_attr["mo_ref"]
        #@logger.debug("cluster rp:#{cluster_resource_pool_attr["mo_ref"]}")
        cluster.datacenter            = datacenter
        cluster.share_datastores      = fetch_datastores(@client.get_datastores_by_cs_mob(cluster_mob),
                                                         datacenter.share_datastore_pattern)
        cluster.local_datastores      = fetch_datastores(@client.get_datastores_by_cs_mob(cluster_mob),
                                                         datacenter.local_datastore_pattern)

        # make sure share_datastores and local_datastores are mutually exclusive
        #share_datastore_names = cluster.share_datastores.map { |ds| ds.name }
        #local_datastore_names = cluster.local_datastores.map { |ds| ds.name }

        #if (share_datastore_names & local_datastore_names).length != 0 && !datacenter.allow_mixed_datastores
        #  raise("datastore patterns are not mutually exclusive non-persistent are #{share_datastore_names.pretty_inspect}\n " +
        #        "local are: #{local_datastore_names.pretty_inspect} \n , " +
        #  "please use allow_mixed_datastores director configuration parameter to allow this")
        #end
        #@logger.debug("share datastores are #{cluster.share_datastores} " +
        #              "local datastores are #{cluster.local_datastores}")

        cluster.hosts = fetch_hosts(cluster, cluster_mob)

        clusters[cluster.name] = cluster
      end
      clusters
    end

    def fetch_resource_pool(cluster_mob, resource_pool_name)

      resource_pool_mobs = @client.get_rps_by_cs_mob(cluster_mob)
      @logger.debug("resource_pool_mobs: #{resource_pool_mobs.pretty_inspect}")

      resource_pool_mobs.each do |resource_pool_mob|
        attr = @client.ct_mob_ref_to_attr_hash(resource_pool_mob, "RP")
        @logger.debug("resource pool in vc :#{attr["name"]} is same as #{resource_pool_name}?")
        if attr["name"] == resource_pool_name
          return attr
        end
      end

      # Get list of resource pools under this cluster
      @logger.info("Could not find requested resource pool #{resource_pool_name} under cluster #{cluster_mob}")
      nil
    end

    def fetch_hosts(cluster, cluster_mob)
      hosts = {}
      host_mobs = @client.get_hosts_by_cs_mob(cluster_mob)
      host_mobs.each do |host_mob|
        attr = @client.ct_mob_ref_to_attr_hash(host_mob, "HS")
        host                    = Host.new
        host.cluster            = cluster
        host.datacenter         = cluster.datacenter
        host.mob                = attr["mo_ref"]
        host.name               = attr["name"]

        @logger.debug("Found host: #{host.name} @ #{host.mob}")

        host.datastores         = @client.get_datastores_by_host_mob(host_mob)
        host.total_memory       = attr["total_memory"]
        host.cpu_limit          = attr["cpu_limit"].to_i
        host.mem_over_commit    = @mem_over_commit
        host.unaccounted_memory = 0

        host.share_datastores = fetch_datastores(host.datastores,
                                                 host.datacenter.share_datastore_pattern)

        host.local_datastores = fetch_datastores(host.datastores,
                                                 host.datacenter.local_datastore_pattern)

        #@logger.debug("host:#{host.name} share datastores are #{host.share_datastores}")
        #@logger.debug("host:#{host.name} local datastores are #{host.local_datastores}")

        host.vms = fetch_vms_by_host(cluster, host, host_mob)
        hosts[host.name] = host
      end
      hosts
    end

    def fetch_vms_by_host(cluster, host, host_mob)
      vms = {}
      vm_mobs = @client.get_vms_by_host_mob(host_mob)
      return vms if vm_mobs.nil?
      vm_mobs.each do |vm_mob|
        @logger.debug("vm_mob:#{vm_mob.pretty_inspect}")
        vm_existed = @client.ct_mob_ref_to_attr_hash(vm_mob, "VM")
        vm = VHelper::CloudManager::VmInfo.new(vm_existed["name"], @logger)

        #update vm info with properties
        @client.update_vm_with_properties_string(vm, vm_existed)
        vm.host_name = host.name

        #update disk info
        @logger.debug("vm_mob:#{vm_mob.pretty_inspect}")
        disk_attrs = @client.get_disks_by_vm_mob(vm_mob)
        disk_attrs.each do |attr|
          disk = vm.disk_add(attr['size'], attr['path'], attr['scsi_num']) 
          datastore_name = @client.get_ds_name_by_path(attr['path'])
          disk.datastore_name = datastore_name
        end

        cluster.vms[vm.name] = vm
        vms[vm.name] = vm
      end
      vms
    end

    # OK finished
    def fetch_datastores(datastore_mobs, match_pattern)
      datastores = {}
      datastore_mobs.each do |datastore_mob|
        attr = @client.ct_mob_ref_to_attr_hash(datastore_mob, "DS")
        next unless isMatched?(attr["name"], match_pattern)
        datastore                   = Datastore.new
        datastore.mob               = attr["mo_ref"]
        datastore.name              = attr["name"]

        #@logger.debug("Found datastore: #{datastore.name} @ #{datastore.mob}")

        datastore.free_space        = attr["freeSpace"]
        datastore.total_space       = attr["maxSpace"]
        datastore.unaccounted_space = 0
        datastores[datastore.name] = datastore
      end
      datastores
    end

    def isMatched?(name, match_pattern)
      #TODO match_pattern is an array
      true
    end

    def find_cs_datastores_by_name(cluster, name)
      datastore = cluster.share_datastores[name]
      return datastore if datastore
      cluster.local_datastores[name]
    end
  end
end

