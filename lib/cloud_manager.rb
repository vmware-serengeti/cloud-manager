require 'fog'
require 'json'
require "cloud_manager/log"
require "cloud_manager/cloud_item"
require "cloud_manager/network_res"
require "cloud_manager/vm"
require "cloud_manager/utils"
require "cloud_manager/resources"
require 'cloud_manager/group'
require "cloud_manager/vm_group"
require 'cloud_manager/cluster_diff'
require "cloud_manager/cloud_placement"
require "cloud_manager/wait_ready"
require "cloud_manager/deploy"
require "cloud_manager/cloud_deploy"
require "cloud_manager/client"
require "cloud_manager/client_fog"
require "cloud_manager/iaas_progress"
require "cloud_manager/iaas_result"
require "cloud_manager/iaas_task"
require "cloud_manager/cloud_progress"
require "cloud_manager/cloud_create"
require "cloud_manager/cloud_operations"
require 'cloud_manager/cloud'
require 'cloud_manager/cluster'

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
