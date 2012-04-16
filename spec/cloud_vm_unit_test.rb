module VHelper; end
require "rubygems"
require "tmpdir"
require 'openssl'
require 'tempfile'
require 'yaml'
require 'erb'
require 'pp'

require './spec/config'
require 'cloud_manager'
require './spec/fog_dummy'

WDC_CONFIG_FILE = "./spec/ut.wdc.yaml"
VC_CONFIG_FILE = "./spec/ut.vc.yaml"
WDC_DEF_CONFIG_FILE_1 = "./spec/ut.wdc_def.yaml"
DC_DEF_CONFIG_FILE_1 = "./spec/ut.dc_def1.yaml"
DC_DEF_CONFIG_FILE_2 = "./spec/ut.dc_def2.yaml"

def ut_test_env
  info = {}
  vcenter = YAML.load(File.open(VC_CONFIG_FILE))
  cluster_req_1 = YAML.load(File.open(DC_DEF_CONFIG_FILE_1))
  info["cluster_definition"] = cluster_req_1
  info["cloud_provider"] = vcenter
  puts("cluster_def : #{cluster_req_1}")
  puts("provider: #{vcenter}")
  info
end

def wdc_test_env
  info = {}
  vcenter = YAML.load(File.open(WDC_CONFIG_FILE))
  cluster_req_1 = YAML.load(File.open(WDC_DEF_CONFIG_FILE_1))
  info["cluster_definition"] = cluster_req_1
  info["cloud_provider"] = vcenter
  puts("cluster_def : #{cluster_req_1}")
  puts("provider: #{vcenter}")
  info
end

begin
  puts "Please input \n"
  puts "\t1-->Create in UT\n"
  puts "\t2-->Create in wdc\n"
  puts "\t3-->Delete in UT\n"
  puts "\t4-->Delete in wdc\n"
  puts "\t5-->List all vm in UT\n"
  puts "\t10-->Delete all UT vm\n"
  puts "\t11-->DEL all vm-XXXX vm \n"
  puts "\t12-->show all VMs in vsPhere\n"

  opt = gets.chomp
  opt = opt.to_i
  info = {}
  puts "You select #{opt}"
  case opt
  when 1 then
    p "##Test UT"
    info = ut_test_env
    cloud = VHelper::CloudManager::Manager.create_cluster(info, :wait => false)
    while !cloud.wait_for_completion
      puts("ut process:#{cloud.get_progress.progress}")
      sleep(5)
    end
    puts("ut finished")
  when 2 then
    puts "##Test WDC"
    info = wdc_test_env
    cloud = VHelper::CloudManager::Manager.create_cluster(info, :wait => true)
    while !cloud.wait_for_completion()
      progress = cloud.get_progress
      puts("ut process:#{progress.progress}")
      puts("ut process:#{progress.results}")
      puts("ut process:#{progress.progress}")
      sleep(5)
    end
  when 3 then #Delete Cluster
    puts "## Delete Cluster in UT"
    info = ut_test_env
    cloud = VHelper::CloudManager::Manager.delete_cluster(info, :wait => true)
    while !cloud.wait_for_completion()
      puts("delete ut process:#{cloud.get_progress}")
      sleep(1)
    end
  when 4 then #Delete Cluster
    puts "## Delete Cluster in WDC"
    info = wdc_test_env
    cloud = VHelper::CloudManager::Manager.delete_cluster(info, :wait => true)
    while !cloud.wait_for_completion()
      puts("delete ut process:#{cloud.get_progress}")
      sleep(1)
    end
  when 5 then #List vms in Cluster
    vcenter = YAML.load(File.open(WDC_CONFIG_FILE))
    cluster_req_1 = YAML.load(File.open(WDC_DEF_CONFIG_FILE_1))
    info["cluster_definition"] = cluster_req_1
    info["cloud_provider"] = vcenter
    puts("cluster_def : #{cluster_req_1}")
    puts("provider: #{vcenter}")
    result = VHelper::CloudManager::Manager.list_vms_cluster(info)
    puts("##result:#{result.pretty_inspect}")
  when 10 then #DEL all XXXX vm
  when 11 then #Show All vm
  when 100 then #show YAML file
    p "## Test ut.dc.yaml\n"
    CONFIG_FILE = "../test/ut.dc.yaml"
    info = YAML.load(File.open(CONFIG_FILE))
    puts("yaml is #{info}")
  else
    puts("Unknow test case!\n")
  end
rescue => e
  puts("#{e} - #{e.backtrace.join("\n")}")
end
