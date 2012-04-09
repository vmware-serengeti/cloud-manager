module VHelper; end
require "rubygems"
require "tmpdir"
require 'logger'
require 'openssl'
require 'tempfile'
require 'yaml'
require 'erb'

require '../src/vsphere_cloud'
require '../test/fog_dummy'

VC_CONFIG_FILE = "../test/ut.vc.yaml"
DC_DEF_CONFIG_FILE_1 = "../test/ut.dc_def1.yaml"
DC_DEF_CONFIG_FILE_2 = "../test/ut.dc_def2.yaml"
vcenter = YAML.load(File.open(VC_CONFIG_FILE))
cluster_req_1 = YAML.load(File.open(DC_DEF_CONFIG_FILE_1))
cluster_req_2 = YAML.load(File.open(DC_DEF_CONFIG_FILE_2))

class Logger
  def initialize()
    puts "initiated UT logger"
  end
  def info(msg)
    puts "INFO: #{msg2str(msg)}"
  end

  def debug(msg)
    puts "DEBUG: #{msg2str(msg)}"
  end

  def inspect
    "<utLogger>"
  end

  def msg2str(msg)
    case msg
    when ::String
      msg
    when ::Exception
      "EXCEPTION #{ msg.message } (#{ msg.class })\n" <<
      (msg.backtrace || []).join("\n")
    else
      msg.inspect
    end
  end
end

logger = Logger.new()

options = { "cloud_provider" => vcenter, "cluster_definition" => cluster_req_1 ,"logger" => logger }


cloud = (options)

begin
  puts "Please input \n"
  puts "\t1-->Create\n"
  puts "\t2-->Update\n"
  puts "\t10-->Delete all UT vm\n"
  puts "\t11-->DEL all vm-XXXX vm \n"
  puts "\t12-->show all VMs in vsPhere\n"

  opt = gets.chomp
  opt = opt.to_i
  puts "You select #{opt}"
  case opt
  when 1 then
    p "##Test UT"
    cloud = VHelper::VSphereCloud::Cloud.createService(options, :"sync" => true)
    while !cloud.wait_complete()
      logger.debug("ut result :#{cloud.get_result}")
      sleep(1)
    end

  when 2 then #Upadte Cluster
  when 10 then #DEL all vh-XXXX vm
  when 11 then #DEL all vm-XXXX vm
  when 12 then #Show All vm
  when 100 then #show YAML file
    p "## Test ut.dc.yaml\n"
    CONFIG_FILE = "../test/ut.dc.yaml"
    info = YAML.load(File.open(CONFIG_FILE))
    logger.debug("yaml is #{info}")
  else
    p "Unknow test case!\n"
  end
rescue => e
  logger.debug("#{e} - #{e.backtrace.join("\n")}")
end
