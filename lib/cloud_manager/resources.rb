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
    class Resources

      include Serengeti::CloudManager::Utils
      class Datacenter
        attr_accessor :mob
        attr_accessor :name
        attr_accessor :clusters
        attr_accessor :port_group
        attr_accessor :vm_template
        attr_accessor :racks
        attr_accessor :share_datastore_pattern
        attr_accessor :local_datastore_pattern
        attr_accessor :spec
        attr_accessor :hosts
        attr_accessor :resource_pools
        def initialize
          resource_pools = {}
          hosts = {}
        end
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
          "<Datastore: #{@mob} / #{@name} size(#{real_free_space}MB / #{@free_space}MB / #{@total_space}MB)>"
        end
        def initialize
          @unaccounted_space = 0
        end
      end

      class Cluster
        attr_accessor :mob
        attr_accessor :name
        attr_accessor :datacenter
        attr_accessor :resource_pools
        attr_accessor :hosts
        attr_accessor :idle_cpu
        attr_accessor :total_memory
        attr_accessor :free_memory
        attr_accessor :unaccounted_memory
        attr_accessor :mem_over_commit
        attr_accessor :vms
        attr_reader   :vc_req
        attr_accessor :disconnected_hosts

        def real_free_memory
          @free_memory - @unaccounted_memory * @mem_over_commit
        end

        def inspect
          "<Cluster: #{@mob} / #{@name}>"
        end

        def initialize
          @disconnected_hosts = []
        end
      end

      class ResourcePool
        attr_accessor :mob
        attr_accessor :name
        attr_accessor :shares
        attr_accessor :host_used_mem
        attr_accessor :guest_used_mem
        attr_accessor :limit_mem    #MB
        attr_accessor :free_memory
        attr_accessor :unaccounted_memory
        attr_accessor :config_mem
        attr_accessor :cluster
        attr_accessor :rev_used_mem
        attr_accessor :used_counter
        def real_free_memory
          @free_memory - @unaccounted_memory
        end
        def inspect
          "<Resource Pool: #{@mob} / #{@name}, #{real_free_memory}MB limit:#{@limit_mem}MB in #{@cluster.inspect} c:#{@used_counter}>"
        end
        def initialize
          @used_counter = 0
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
        attr_accessor :used_mem
        attr_accessor :used_cpu
        attr_accessor :connection_state
        attr_accessor :place_share_datastores
        attr_accessor :place_local_datastores

        def real_free_memory
          (@free_memory - @unaccounted_memory)
        end

        def inspect
          msg = "<Host: #{@mob} / #{@name}, #{real_free_memory}MB/#{@free_memory}MB/#{@total_memory}MB>, vm #{@vms.size}\n datastores:\n"
          share_datastores.each_value { |datastore|msg<<"share "<<datastore.inspect }
          local_datastores.each_value { |datastore|msg<<"local "<<datastore.inspect }
          msg
        end
      end

      include Serengeti::CloudManager::Parallel
      include Serengeti::CloudManager::Utils
      #########################################################
      # Begin Resource functions
      def initialize(client, cloud, mem_over_commit = 1.0)
        @client       = client
        @cloud        = cloud
        @datacenter   = {}
        @lock         = Mutex.new
        @mem_over_commit  = mem_over_commit
      end

      def fetch_vm_by_moid(vm_ref, dc_mob)
        mob = @client.get_vm_mob_ref_by_moid(vm_ref, dc_mob)
        vm = VmInfo.fetch_vm_from_cloud(mob, @cloud)
        logger.debug("fetch vm:#{vm.pretty_inspect}")
        vm
      end

      def fetch_datacenter(datacenter_name)
        datacenter_mob = @client.get_dc_mob_ref_by_path(datacenter_name)
        if datacenter_mob.nil?
          logger.debug("Do not find the datacenter: #{datacenter_name}")
          raise "Do not find the datacenter: #{datacenter_name}"
        end
        attr = @client.ct_mob_ref_to_attr_hash(datacenter_mob, "DC")

        datacenter                      = Datacenter.new
        datacenter.mob                  = attr['mo_ref']
        datacenter.name                 = datacenter_name

        logger.debug("Found datacenter: #{datacenter.name} @ #{datacenter.mob}")

        #raise "Missing share_datastore_pattern in director config" if @cloud.vc_share_datastore_pattern.nil?
        logger.debug("share pattern:#{config.vc_share_datastore_pattern}")
        logger.debug("local pattern:#{config.vc_local_datastore_pattern}")
        datacenter.share_datastore_pattern = config.vc_share_datastore_pattern
        datacenter.local_datastore_pattern = config.vc_local_datastore_pattern

        datacenter.racks = @cloud.racks

        datacenter.vm_template = fetch_vm_by_moid(config.cloud_template_id, datacenter_mob)
        datacenter.port_group = @client.get_portgroups_by_dc_mob(datacenter_mob)
        datacenter.hosts = {}
        datacenter.resource_pools = {}
        datacenter.clusters = fetch_clusters(datacenter, datacenter_mob)

        logger.debug("datacenter hosts:#{datacenter.hosts.pretty_inspect}")
        datacenter
      end

      # Fetch clusters information
      def fetch_clusters(datacenter, datacenter_mob)
        cluster_mobs = @client.get_clusters_by_dc_mob(datacenter_mob)

        clusters = {}
        group_each_by_threads(cluster_mobs, :callee => "fetch clusters") do |cluster_mob|
          attr = @client.ct_mob_ref_to_attr_hash(cluster_mob, "CS")
          # chose cluster in cluster_names
          next unless @cloud.vc_req_rps.key?(attr["name"])

          resouce_names = @cloud.vc_req_rps[attr['name']]
          logger.debug("Use cluster :#{attr["name"]} and checking resource pools")
          cluster                     = Cluster.new
          resource_pools = fetch_resource_pool(cluster, cluster_mob, resouce_names)
          if resource_pools.empty?
            logger.debug("Do not find any reqired resource #{resouce_names.pretty_inspect} in cluster :#{attr["name"]}")
            next
          end

          cluster.mem_over_commit     = @mem_over_commit
          cluster.mob                 = attr["mo_ref"]
          cluster.name                = attr["name"]
          cluster.vms                 = {}

          logger.debug("Found cluster: #{cluster.name} @ #{cluster.mob}")

          cluster.resource_pools      = resource_pools
          cluster.datacenter          = datacenter
          cluster.hosts = fetch_hosts(cluster, cluster_mob)

          datacenter.hosts.merge!(cluster.hosts)
          #logger.debug("cluster hosts:#{cluster.hosts.pretty_inspect}")
          datacenter.resource_pools[cluster.name] = cluster.resource_pools

          clusters[cluster.name] = cluster
        end
        clusters
      end

      def fetch_resource_pool(cluster, cluster_mob, resource_pool_names)
        resource_pool_mobs = @client.get_rps_by_cs_mob(cluster_mob)
        resource_pools = {}

        resource_pool_mobs.each do |resource_pool_mob|
          attr = @client.ct_mob_ref_to_attr_hash(resource_pool_mob, "RP")
          logger.debug("resource pool in vc :#{attr["name"]} is in #{resource_pool_names}?")
          next unless resource_pool_names.include?(attr["name"])
          rp = ResourcePool.new
          rp.mob            = attr["mo_ref"]
          rp.name           = attr["name"]
          rp.shares         = attr["shares"]
          rp.host_used_mem  = attr["host_used_mem"]
          rp.guest_used_mem = attr["guest_used_mem"]
          rp.limit_mem      = attr["limit_mem"]
          rp.config_mem     = attr["config_mem"]
          rp.rev_used_mem   = attr["rev_used_mem"]
          rp.free_memory = rp.limit_mem.to_i
          rp.cluster        = cluster
          if rp.limit_mem.to_i != -1
            rp.free_memory  = rp.limit_mem - rp.host_used_mem - rp.guest_used_mem
          end
          rp.unaccounted_memory = 0
          logger.debug("Can use rp: #{rp.name} free mem:#{rp.free_memory} \n => #{attr.pretty_inspect}")
          resource_pools[rp.name] = rp
        end

        # Get list of resource pools under this cluster
        logger.warn("Could not find requested resource pool #{resource_pool_names} under cluster #{cluster_mob}") if resource_pools.empty?
        resource_pools
      end

      def fetch_hosts(cluster, cluster_mob)
        hosts = {}
        host_mobs = @client.get_hosts_by_cs_mob(cluster_mob)
        group_each_by_threads(host_mobs, :callee => "fetch hosts in #{cluster.name}") do |host_mob|
          attr = @client.ct_mob_ref_to_attr_hash(host_mob, "HS")
          connection_state   = attr["connection_state"]
          if connection_state != 'connected'
            logger.debug("host #{attr["name"]} is not connected ")
            cluster.disconnected_hosts << attr["name"]
            next
          end
          logger.debug("host #{attr["name"]} is connected.")

          host                    = Host.new
          host.cluster            = cluster
          host.datacenter         = cluster.datacenter
          host.mob                = attr["mo_ref"]
          host.name               = attr["name"]

          logger.debug("Found host: #{host.name} @ #{host.mob}")

          host.datastores         = @client.get_datastores_by_host_mob(host_mob)
          host.total_memory       = attr["total_memory"]
          host.cpu_limit          = attr["cpu_limit"].to_i
          host.used_mem           = attr["used_mem"].to_i
          host.used_cpu           = attr["used_cpu"].to_i
          host.connection_state   = connection_state
          host.mem_over_commit    = @mem_over_commit
          host.free_memory        = host.total_memory.to_i - host.used_mem.to_i
          host.unaccounted_memory = 0

          host.share_datastores = fetch_datastores(host.datastores,
                                                   host.datacenter.share_datastore_pattern)
          logger.debug("warning: no matched sharestores in host:#{host.name}") if host.share_datastores.empty?

          host.local_datastores = fetch_datastores(host.datastores,
                                                   host.datacenter.local_datastore_pattern)
          logger.debug("warning: no matched localstores in host:#{host.name}") if host.share_datastores.empty?

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
          #logger.debug("vm_mob:#{vm_mob.pretty_inspect}")
          vm = VmInfo.fetch_vm_from_cloud(vm_mob, @cloud) { |name| @cloud.vm_is_this_cluster?(name) }
          next if vm.nil?

          vm.host_name = host.name
          vms[vm.name] = vm
        end
        vms
      end

      # OK finished
      def fetch_datastores(datastore_mobs, match_patterns)
        datastores = {}
        return datastores if match_patterns.nil?
        datastore_mobs.each do |datastore_mob|
          attr = @client.ct_mob_ref_to_attr_hash(datastore_mob, "DS")
          next unless isMatched?(attr["name"], match_patterns)
          datastore                   = Datastore.new
          datastore.mob               = attr["mo_ref"]
          datastore.name              = attr["name"]

          #logger.debug("Found datastore: #{datastore.name} @ #{datastore.mob}")

          datastore.free_space        = attr["freeSpace"].to_i / (1024 *1024)
          datastore.total_space       = attr["capacity"].to_i / (1024*1024)
          datastore.unaccounted_space = 0
          datastores[datastore.name]  = datastore
        end
        datastores
      end

      def isMatched?(name, match_patterns)
        #logger.debug("isMatched? #{name}, #{match_patterns.pretty_inspect}")
        match_patterns.each { |pattern| return true if name.match(pattern) }
        #logger.debug("Not Match? ")
        false
      end

    end
  end
end

