###############################################################################
#   Copyright (c) 2012 VMware, Inc. All Rights Reserved.
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

# @version 0.5.0

require 'json'
module Serengeti
  module CloudManager

    class Cloud
      class NetworkRes
        include Serengeti::CloudManager::Utils
        IP = '(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])'
        def initialize(networking)
          @net_config = networking

          range_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}-#{IP}\.#{IP}\.#{IP}\.#{IP}$")
          ip_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}$")
          @net_config.each do |conf|
            conf['ip_pool'] = {}
            next if (conf['type'] != 'static')
            conf['ip'].each do |ip|
              next if put_range_to_ip_pool(ip, conf['ip_pool'], range_check)
              single_result = ip_check.match(ip)
              conf['ip_pool'][ip] = 1 if (single_result)
            end
          end
          logger.debug("IP net_config:#{@net_config.pretty_inspect}")
          @lock = Mutex.new
        end

        def card_op
          @net_config.each { |network| yield network}
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

        def dhcp?(card);  @net_config[card]['type'] == 'dhcp'; end
        def static?(card); @net_config[card]['type'] == 'static'; end
        def port_group(card); @net_config[card]['port_group']; end
        def port_groups(); @net_config.map { |net| net['port_group'] } end
        def netmask(card); @net_config[card]['netmask'];end
        def gateway(card); @net_config[card]['gateway'];end
        def dns(card); @net_config[card]['dns']; end
        def card_num; @net_config.size; end
        def not_existed_port_group(net_pg)
          @net_config.each { |net_config| return net_config['port_group'] if !net_pg.key?(net_config['port_group']) }
          nil
        end

        def ip_num(card)
          @lock.synchronize { return @net_config[card]['ip_pool'].size}
        end

        def ip_alloc(card)
          @lock.synchronize { return @net_config[card]['ip_pool'].shift.first}
        end

        def ip_remove(card, ip)
          @lock.synchronize { @net_config[card]['ip_pool'].delete(ip.to_s)}
        end

        def ip_release(card, ip)
          @lock.synchronize { @net_config[card]['ip_pool'][ip.to_s] = 2}
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

          net_config = JSON.parse(config_json)
          ip_remove(net_config['ipaddr']) if net_config['ipaddr']
          'OK'
        end

      end


    end
  end
end

