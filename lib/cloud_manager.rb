require '../fog/lib/fog'
require 'json'
require "lib/cloud_manager/log"
require "lib/cloud_manager/cloud_item"
require "lib/cloud_manager/network_res"
require "lib/cloud_manager/vm"
require "lib/cloud_manager/utils"
require "lib/cloud_manager/resources"
require 'lib/cloud_manager/group'
require "lib/cloud_manager/vm_group"
require 'lib/cloud_manager/cluster_diff'
require "lib/cloud_manager/cloud_placement"
require "lib/cloud_manager/wait_ready"
require "lib/cloud_manager/deploy"
require "lib/cloud_manager/cloud_deploy"
require "lib/cloud_manager/client"
require "lib/cloud_manager/client_fog"
require "lib/cloud_manager/IaasProgress"
require "lib/cloud_manager/IaasResult"
require "lib/cloud_manager/IaasTask"
require "lib/cloud_manager/cloud_progress"
require "lib/cloud_manager/cloud_create"
require "lib/cloud_manager/cloud_operations"
require 'lib/cloud_manager/cloud'
require 'lib/cloud_manager/cluster'

module Serengeti
  module CloudManager
    class Manager
      def self.cluster_helper(parameter, options={})
        cloud = nil
        begin
          cloud = IaasTask.new(parameter['cluster_definition'], parameter['cloud_provider'], parameter['cluster_data'])
          if (options[:wait])
            yield cloud
          else
            # options["sync"] == false
            Thread.new do
              yield cloud
            end
          end
        ensure
          cloud.release_connection if cloud
        end
        cloud
      end

      # TODO describe start/stop/delete/create functions and limitation
      # TODO describe cluster structures and operations
      # TODO add group structures
      def self.start_cluster(parameter, options={})
        cluster_helper(parameter, options) { |cloud| cloud.start }
      end

      def self.stop_cluster(parameter, options={})
        cluster_helper(parameter, options) { |cloud| cloud.stop }
      end

      def self.delete_cluster(parameter, options={})
        cluster_helper(parameter, options) { |cloud| cloud.delete }
      end

      def self.create_cluster(parameter, options={})
        cluster_helper(parameter, options) { |cloud| cloud.create_and_update }
      end

      # TODO change to show_cluster
      def self.list_vms_cluster(parameter, options={})
        cloud = nil
        begin
          cloud = IaasTask.new(parameter["cluster_definition"], parameter["cloud_provider"], parameter['cluster_data'])
          return cloud.list_vms
        ensure
          cloud.release_connection if cloud
        end
      end

      def self.set_log_level(level)
        Serengeti::CloudManager::Cloud.set_log_level(level)
      end
    end
  end
end
