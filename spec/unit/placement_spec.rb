###############################################################################
#    Copyright (c) 2012 VMware, Inc. All Rights Reserved.
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
$:.unshift(File.expand_path("../../../lib/cloud_manager", __FILE__))

require "rubygems"
require "yaml"

require "log"
require "config"
require "utils"
require "vm"
require "vm_group"
require "virtual_node"
require "cloud"
require "exception"
require "placement"
require "placement_impl"

GROUP_DEF_FILE = File.expand_path("../../assets/unit/placement_constraint_groups.yaml", __FILE__)
MAPR_GROUP_NAME = "mapr"
HDFS_GROUP_NAME = "hdfs"
CLIENT_GROUP_NAME = "client"

describe Serengeti::CloudManager::FullPlacement do
  before(:each) do
    groups = YAML.load(File.open(GROUP_DEF_FILE))
    @vm_groups = {}
    groups["groups"].each do |group|
      @vm_groups[group["name"]] = Serengeti::CloudManager::VmGroupInfo.new(group)
    end

    @placement = Serengeti::CloudManager::FullPlacement.new(nil)
    @placement.get_virtual_groups(@vm_groups)
  end

  def hdfs_group
    @vm_groups[HDFS_GROUP_NAME]
  end

  def mapr_group
    @vm_groups[MAPR_GROUP_NAME]
  end

  def client_group
    @vm_groups[CLIENT_GROUP_NAME]
  end

  def place_hdfs_group
    (1..5).each do |num|
      vnode = Serengeti::CloudManager::VirtualNode.new
      vnode.vm_specs << Serengeti::CloudManager::VmSpec.new(hdfs_group, "vm" + num.to_s)
      @placement.assign_host(vnode, "host" + num.to_s)
    end
  end

  it "should filter out existed vm that violate instance_per_host constraint" do
    existed_vms = {}
    {"vm1" => "host1", "vm2"=>"host1", "vm3"=>"host2", "vm4"=> "host3"}.each do |vm_name, host_name|
      vm = Serengeti::CloudManager::VmInfo.new(vm_name, nil)
      vm.host_name = host_name
      # group mapr1 has attribute instance_per_host=2
      vm.group_name = MAPR_GROUP_NAME
      existed_vms[vm_name] = vm
    end
    
    deleted_vms = @placement.clean_cluster(@vm_groups, existed_vms)
    deleted_vms.map {|vm| vm.name}.should eq ["vm3", "vm4"]
  end
  
  it "should raise exception when the cluster is not cleaned before calling get_virtual_nodes" do
    existed_vms = {}
    {"vm1" => "host1", "vm2"=>"host1", "vm3"=>"host2", "vm4"=> "host3"}.each do |vm_name, host_name|
      vm = Serengeti::CloudManager::VmInfo.new(vm_name, nil)
      vm.host_name = host_name
      # mapr group has attribute instance_per_host=2
      vm.group_name = mapr_group.name
      existed_vms[vm_name] = vm
    end
    
    expect {
      @placement.get_virtual_nodes(mapr_group, existed_vms, nil)
    }.to raise_error(Serengeti::CloudManager::PlacementException)
  end

  it "should return correct virtual node set" do
    existed_vms = {}
    {"vm1" => "host1", "vm3"=>"host1"}.each do |vm_name, host_name|
      vm = Serengeti::CloudManager::VmInfo.new(vm_name, nil)
      vm.host_name = host_name
      # mapr group has attribute instance_per_host=2
      vm.group_name = mapr_group.name
      existed_vms[vm_name] = vm
    end

    @placement.get_virtual_nodes(mapr_group, existed_vms, nil).size.should eq 4
  end

  it "should raise exception when available host list is empty" do
    vnode = Serengeti::CloudManager::VirtualNode.new
    vnode.vm_specs << Serengeti::CloudManager::VmSpec.new(mapr_group, "vm1")
    vnode.vm_specs << Serengeti::CloudManager::VmSpec.new(mapr_group, "vm2")
    resource_availability = {'storage' => {}}

    expect {
      @placement.select_host(vnode, resource_availability)
    }.to raise_error(Serengeti::CloudManager::PlacementException)
  end

  it "should raise exception when referred group is not placed first" do
    vnode = Serengeti::CloudManager::VirtualNode.new
    vnode.vm_specs << Serengeti::CloudManager::VmSpec.new(mapr_group, "vm1")
    vnode.vm_specs << Serengeti::CloudManager::VmSpec.new(mapr_group, "vm2")
    resource_availability = {'storage' => {'host1' => 1}}

    expect {
      @placement.select_host(vnode, resource_availability)
    }.to raise_error(Serengeti::CloudManager::PlacementException)
  end

  it "should select correct hosts for STRICT policy" do
    place_hdfs_group

    existed_vms = {}
    {"vm1" => "host1", "vm3"=>"host1"}.each do |vm_name, host_name|
      vm = Serengeti::CloudManager::VmInfo.new(vm_name, nil)
      vm.host_name = host_name
      # mapr group has attribute instance_per_host=2
      vm.group_name = mapr_group.name
      existed_vms[vm_name] = vm
    end

    vnodes = @placement.get_virtual_nodes(mapr_group, existed_vms, nil)

    resource_availability = {'storage' =>
        { 'host1' => 1, 'host6' => 2,
        'host3' => 3, 'host4' => 4,
        'host5' => 5, 'host2' => 6
      }
    }
    selected_hosts = []
    vnodes.each do |vnode|
      host_name = @placement.select_host(vnode, resource_availability)
      @placement.assign_host(vnode, host_name)
      selected_hosts << host_name
    end
    selected_hosts.should eq ["host3", "host4", "host5", "host2"]
  end
  
  it "should raise exception when STRICT policy cannot be satified" do
    place_hdfs_group
    
    vnodes = @placement.get_virtual_nodes(mapr_group, {}, nil)
    resource_availability = {'storage' =>
        { 'host1' => 1, 'host6' => 2,
        'host3' => 3, 'host4' => 4,
        'host5' => 5, 'host7' => 6
      }
    }
                         
    expect {
      vnodes.each do |vnode|
        host_name = @placement.select_host(vnode, resource_availability)
        @placement.assign_host(vnode, host_name)
      end
    }.to raise_error(Serengeti::CloudManager::PlacementException)
  end

  it "should return correct host set for WEAK group association" do
    place_hdfs_group

    existed_vms = {}
    {"vm1" => "host1", "vm3"=>"host2"}.each do |vm_name, host_name|
      vm = Serengeti::CloudManager::VmInfo.new(vm_name, nil)
      vm.host_name = host_name
      # mapr group has attribute instance_per_host=2
      vm.group_name = client_group.name
      existed_vms[vm_name] = vm
    end

    vnodes = @placement.get_virtual_nodes(client_group, existed_vms, nil)
    resource_availability = {'storage' =>
        { 'host1' => 1, 'host6' => 2,
        'host3' => 3, 'host4' => 4,
        'host5' => 5, 'host7' => 6
      }
    }

    selected_hosts = []
    vnodes.each do |vnode|
      host_name = @placement.select_host(vnode, resource_availability)
      @placement.assign_host(vnode, host_name)
      resource_availability['storage'].delete(host_name)
      selected_hosts << host_name
    end
    selected_hosts.should eq ["host3", "host4", "host5", "host1", "host6", "host7"]
  end

end

