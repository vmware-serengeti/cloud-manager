require "lib/cloud_manager/cloud_item"
require "lib/cloud_manager/utils"
require "lib/cloud_manager/resources"
require "lib/cloud_manager/vm_group"
require 'lib/cloud_manager/cluster_diff'
require "lib/cloud_manager/cloud_placement"
require "lib/cloud_manager/cloud_deploy"
require "lib/cloud_manager/client"
require "lib/cloud_manager/client_fog"
require "lib/cloud_manager/vhelper_cloud"
require 'lib/cloud_manager/vsphere_cloud'

module VHelper::CloudManager
  class Manager
    def self.cluster_helper(parameter, options={})
      cloud = IaasTask.new(parameter["cluster_definition"], parameter["cloud_provider"])
      if (options[:wait])
        return yield cloud
      else
        # options["sync"] == false
        Thread.new do
          yield cloud
        end
      end
      cloud
    end

    def self.delete_cluster(parameter, options={})
      cluster_helper(parameter, options) { |cloud| cloud.delete }
    end

    def self.create_cluster(parameter, options={})
      cluster_helper(parameter, options) { |cloud| cloud.create_and_update }
    end

    def self.list_vms_cluster(parameter, options={})
      cluster_helper(parameter, :wait=>true) { |cloud| cloud.list_vms }
    end
  end
end
