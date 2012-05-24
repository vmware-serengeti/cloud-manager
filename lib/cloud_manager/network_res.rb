module Serengeti
  module CloudManager

    class Cloud
      class NetworkRes
        attr_accessor :config

        IP = '(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])'
        def initialize(networking)
          @config = networking
          # TODO ip range handle

          range_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}-#{IP}\.#{IP}\.#{IP}\.#{IP}$")
          ip_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}$")
          @config.each {|conf|
            conf['ip_pool'] = {}
            next if (conf['type'] != 'static')
            conf['ip'].each { |ip|
              next if put_range_to_ip_pool(ip, conf['ip_pool'], range_check)
              single_result = ip_check.match(ip)
              conf['ip_pool'][ip] = 1 if (single_result)
            }
          }
          @lock = Mutex.new
        end

        def range_extend(range, level, out_ip, out_range)
          return out_range[out_ip] = 1 if (level >= 5)
          (range[level]..range[level+4]).each {|ip| range_extend(range, level+1, "#{out_ip}.#{ip}", out_range)}
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

        def ip_num(card); @lock.synchronize { return @config[card]['ip_pool'].size}; end

        def ip_alloc(card) @lock.synchronize { return @config[card]['ip_pool'].shift.first} end

        def ip_remove(card, ip) @lock.synchronize { @config[card]['ip_pool'].delete(ip.to_s)} end

        def ip_release(card, ip)
          @lock.synchronize { @config[card]['ip_pool'][ip.to_s] = 2}
          nil
        end

        def get_vm_network_json(hostname, card)
          config_json = ''
          if (static?(card))
            assign_ip = ip_alloc(card)
            config_json = {
              "device"    => "eth#{card}",
              "bootproto" => "static",
              "ipaddr"    => "#{assign_ip}",
              "netmask"   => netmask(card),
              "gateway"   => gateway(card),
              "hostname"  => hostname.to_s,
              "dnsserver0"=> dns(card)[0],
              "dnsserver1"=> dns(card)[1],
            }.to_json
          else
            config_json = {'device'=>"eth#{card}", 'bootproto'=>'dhcp'}.to_json
          end
          config_json
        end

      end


    end
  end
end

