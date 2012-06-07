require 'spec_helper'

describe "Cluster unit tests" do

  before(:all) do
    @wait = true
    @info = wdc_test_env
  end

  it "Create cluster" do
    cloud = Serengeti::CloudManager::Manager.create_cluster(@info, :wait => @wait)
    while !cloud.finished?
      progress = cloud.get_progress
      sleep(1)
    end
    progress = cloud.get_progress
  end

  it "Check cluster diff function" do
    cloud = Serengeti::CloudManager::Manager.create_cluster(@info, :wait => @wait)
    while !cloud.finished?
      progress = cloud.get_progress
      sleep(1)
    end
    progress = cloud.get_progress
  end

  it "List all vms" do
    result = Serengeti::CloudManager::Manager.list_vms_cluster(@info)
  end

  it "Stop vms in cluster" do
    result = Serengeti::CloudManager::Manager.stop_cluster(@info, :wait => @wait)
    progress = result.get_progress
  end

  it "Start vms in cluster" do
    result = Serengeti::CloudManager::Manager.start_cluster(@info, :wait => @wait)
    progress = result.get_progress
  end

  it "Delete cluster" do
    cloud = Serengeti::CloudManager::Manager.delete_cluster(@info, :wait => @wait)
    while !cloud.finished?
      sleep(1)
    end
    progress = cloud.get_progress
  end

  after(:all) do
    @wait = nil
    @info = nil
  end

end
