module VHelper::CloudManager
  class VHelperCloud
    class NetworkRes
      attr_accessor :configure

      IP = '(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])'
      def initialize(networking)
        @configure = networking
        # TODO ip range handle
        
        range_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}-#{IP}\.#{IP}\.#{IP}\.#{IP}$")
        ip_check = Regexp.new("^#{IP}\.#{IP}\.#{IP}\.#{IP}$")
        @configure.each {|conf|
          conf['ip_pool'] = []
          next if (conf['type'] != 'static')
          conf['ip'].each { |ip|
            next if put_range_to_ip_pool(ip, conf['ip_pool'], range_check)
            single_result = ip_check.match(ip)
            conf['ip_pool'] << ip if (single_result)
          }
        }
        @lock = Mutex.new
      end

      def range_extend(range, level, out_ip, out_range)
        return out_range << out_ip if (level >= 5)
        (range[level]..range[level+4]).each {|ip| range_extend(range, level+1, "#{out_ip}.#{ip}", out_range)}
      end

      def put_range_to_ip_pool(ip_range, pool, range_check)
        range_result = range_check.match(ip_range)
        return nil if range_result.nil?
        range_extend(range_result, 2, range_result[1].to_s, pool)
      end

      def dhcp?(card);  @configure[card]['type'] == 'dhcp'; end
      def static?(card); @configure[card]['type'] == 'static'; end
      def port_group(card); @configure[card]['port_group']; end
      def netmask(card); @configure[card]['netmask'];end
      def gateway(card); @configure[card]['gateway'];end
      def dns(card); @configure[card]['dns']; end
      def card_num; @configure.size; end

      def alloc_ip(card)
        @lock.synchronize { return @configure[card]['ip_pool'].shift}
      end

      def remove_ip(card, ip)
        # TODO
        #@lock.synchronize { @configure[card]['ip_pool'].delete_if(|v| v == ip}
      end

      def release_ip(card, ip)
        @lock.synchronize { @configure[card]['ip_pool'] << ip}
        nil
      end

      def get_vm_network_json(hostname, card)
        config_json = ''
        if (static?(card))
          assign_ip = alloc_ip(card)
          config_json = {
            "device"    => "eth#{card}",
            "bootproto" => "static",
            "ipaddr"    => "#{assign_ip}",
            "netmask"   => netmask(card),
            "gateway"   => gateway(card),
            "hostname"  => hostname,
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

