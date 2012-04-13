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
    def self.delete_cluster(parameter, options={})
      cloud = IaasTask.new(parameter["cluster_definition"], parameter["cloud_provider"])
      if (options[:wait])
        cloud.delete
      else
        # options["sync"] == false
        Thread.new do
          cloud.delete
        end
      end
      cloud
    end

    def self.create_cluster(parameter, options={})
      cloud = IaasTask.new(parameter["cluster_definition"], parameter["cloud_provider"])
      if (options[:wait])
        cloud.create_and_update
      else
        # options["sync"] == false
        Thread.new do
          cloud.create_and_update
        end
      end
      cloud
    end

    def self.query_cluster(parameter, options={})
      cloud = IaasTask.new(parameter["cluster_definition"], parameter["cloud_provider"])
      if (options[:wait])
        cloud.query
      else
        # options["sync"] == false
        Thread.new do
          cloud.query
        end
      end
      cloud
    end
  end
end
