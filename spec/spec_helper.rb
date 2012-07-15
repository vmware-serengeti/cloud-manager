require 'json'
require 'yaml'
require 'pp'
require 'cloud_manager'

def ut_configure_file
  ENV["UT_CLOUD_PROVIDER_FILE"] || "./ut.yaml"
end
def func_configure_file
  ENV["FUNC_CLOUD_PROVIDER_FILE"] || "./func.yaml"
end

def load_test_env(provider_file, type)
  info = {}
  all_config = YAML.load(File.open(provider_file))
  vcenter = all_config['cloud_provider']
  cluster_def = YAML.load(File.open(all_config['config']['cluster_def_file']))
  info["cluster_definition"] = cluster_def
  info["cloud_provider"] = vcenter
  info['type'] = type
  info['config'] = all_config['config']
  Serengeti::CloudManager.config.update(info['config'])
  puts("cluster_def : #{cluster_def.pretty_inspect}")
  puts("provider: #{vcenter.pretty_inspect}")
  puts("config: #{info['config'].pretty_inspect}")
  info
end

