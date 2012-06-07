require 'spec'
require 'fog'
require 'json'
require 'yaml'
require 'pp'
require 'cloud_manager'

WDC_CONFIG_FILE = "./spec/func.wdc.yaml"
VC_CONFIG_FILE = "./spec/ut.vc.yaml"
WDC_DEF_CONFIG_FILE_1 = "./spec/func.wdc_def.yaml"
DC_DEF_CONFIG_FILE_1 = "./spec/ut.dc_def1.yaml"
DC_DEF_CONFIG_FILE_2 = "./spec/ut.dc_def2.yaml"

def ut_test_env
  info = {}
  vcenter = YAML.load(File.open(VC_CONFIG_FILE))
  cluster_req_1 = YAML.load(File.open(DC_DEF_CONFIG_FILE_1))
  cluster_req_2 = YAML.load(File.open(DC_DEF_CONFIG_FILE_2))
  info["cluster_definitions"] = [cluster_req_1, cluster_req_2]
  info["cluster_definition"] = info["cluster_definitions"].first
  info["cloud_provider"] = vcenter
  info['type'] = 'UT'
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
  info['type'] = 'WDC'
  puts("cluster_def : #{cluster_req_1}")
  puts("provider: #{vcenter}")
  info
end
