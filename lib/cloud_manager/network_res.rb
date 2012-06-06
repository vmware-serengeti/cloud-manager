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

# @since serengeti 0.5.0
# @version 0.5.0
# @author haiyu wang

module Serengeti
  module CloudManager

    class Cloud
      class NetworkRes
        attr_accessor :config

        IP = '(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])'
        def initialize(networking)
          @config = networking
          @logger = Serengeti::CloudManager::Cloud.Logger

          range_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}-#{IP}\.#{IP}\.#{IP}\.#{IP}$")
          ip_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}$")
          @config.each do |conf|
            conf['ip_pool'] = {}
            next if (conf['type'] != 'static')
            conf['ip'].each do |ip|
              next if put_range_to_ip_pool(ip, conf['ip_pool'], range_check)
              single_result = ip_check.match(ip)
              conf['ip_pool'][ip] = 1 if (single_result)
            end
          end
          @logger.debug("IP config:#{@config.pretty_inspect}")
          @lock = Mutex.new
        end

        def range_extend(range, level, out_ip, out_range)
          return out_range[out_ip] = 1 if (level >= 5)
          (range[level]..range[level+4]).each { |ip| range_extend(range, level+1, "#{out_ip}.#{ip}", out_range) }
        end

        def put_range_to_ip_pool(ip_range, pool, range_check)
          range = range_check.match(ip_range)
          return nil if range.nil?
          (range[1]..range[5]).each { |ip| range_extend(range, 2, ip.to_s, pool)}
        end

        def dhcp?(card);  @config[card]['type'] == 'dhcp'; end
        def static?(card); @config[card]['type'] == 'static'; end
        def port_group(card); @config[card]['port_group']; end
        def netmask(card); @config[card]['netmask'];end
        def gateway(card); @config[card]['gateway'];end
        def dns(card); @config[card]['dns']; end
        def card_num; @config.size; end
        def not_existed_port_group(net_pg)
          @config.each { |config| return config['port_group'] if !net_pg.key?(config['port_group']) }
          nil
        end

        def ip_num(card); @lock.synchronize { return @config[card]['ip_pool'].size}; end

        def ip_alloc(card) @lock.synchronize { return @config[card]['ip_pool'].shift.first} end

        def ip_remove(card, ip) @lock.synchronize { @config[card]['ip_pool'].delete(ip.to_s)} end

        def ip_release(card, ip)
          @lock.synchronize { @config[card]['ip_pool'][ip.to_s] = 2}
          nil
        end

        def get_vm_network_json(card)
          config_json = ''
          if (static?(card))
            assign_ip = ip_alloc(card)
            #return nil if assign_ip.nil?
            config_json = {
              "device"    => "eth#{card}",
              "bootproto" => "static",
              "ipaddr"    => "#{assign_ip}",
              "netmask"   => netmask(card),
              "gateway"   => gateway(card),
              "hostname"  => '',
              "dnsserver0"=> dns(card)[0],
              "dnsserver1"=> dns(card)[1],
            }.to_json
          else
            config_json = {'device'=>"eth#{card}", 'bootproto'=>'dhcp'}.to_json
          end
          config_json
        end

        def free_vm_network_json(card, config_json)
          return 'OK' if !static?(card)

          config = JSON.parse(config_json)
          ip_remove(config['ipaddr']) if config['ipaddr']
          'OK'
        end

      end


    end
  end
end

