require 'spec_helper'

def check_cloud_op_finish(cloud)
  progress = cloud.get_progress
  pass = true
  progress.finished.should == true
  pass = yield(progress.result.error_msg, progress.result.servers) if block_given?
  pass.should == true
end

def check_cloud_op_process(cloud)
  progress = cloud.get_progress
  progress.finished.should == false
  pass = true
  pass yield(progress.result.error_msg, progress.result) if block_given?
  pass.should == true
end

describe "Cluster unit tests" do

  before(:all) do
    provider_file = ut_configure_file
    puts "config file:#{provider_file}"
    @info = load_test_env(provider_file, 'UT')
    Serengeti::CloudManager.config.update(@info['config'])
    @wait = true
  end

  it "Create cluster" do
    cloud = Serengeti::CloudManager::Manager.create_cluster(@info, :wait => @wait)
    while !cloud.finished?
      check_cloud_op_process(cloud) do
        #TODO add create progress checking
        true
      end
      sleep(1)
    end
    check_cloud_op_finish(cloud) do
      #TODO add create finish checking
      true
    end
  end

  it "Check cluster diff function" do
    cloud = Serengeti::CloudManager::Manager.create_cluster(@info, :wait => @wait)
    while !cloud.finished?
      check_cloud_op_process(cloud)
      sleep(1)
    end
    check_cloud_op_finish(cloud)
  end

  it "List all vms" do
    result = Serengeti::CloudManager::Manager.list_vms_cluster(@info)
  end

  it "Stop vms in cluster" do
    cloud = Serengeti::CloudManager::Manager.stop_cluster(@info, :wait => @wait)
    while !cloud.finished?
      check_cloud_op_process(cloud)
      sleep(1)
    end
    check_cloud_op_finish(cloud)
  end

  it "Start vms in cluster" do
    cloud = Serengeti::CloudManager::Manager.start_cluster(@info, :wait => @wait)
    check_cloud_op_finish(cloud)
  end

  it "Delete cluster" do
    cloud = Serengeti::CloudManager::Manager.delete_cluster(@info, :wait => @wait)
    while !cloud.finished?
      check_cloud_op_process(cloud)
      sleep(1)
    end
    check_cloud_op_finish(cloud)
  end

  after(:all) do
    @wait = nil
    @info = nil
  end

end
