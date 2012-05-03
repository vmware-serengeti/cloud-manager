module VHelper::CloudManager
  class VHelperCloud
    class NetworkRes
      attr_accessor :configure

      def initialize(networking)
        @configure = networking
        # TODO ip range handle
        @configure.each {|conf|
          conf['ip_pool'] = []
          conf['ip'].each { |ip|
            next if put_range_to_ip_pool(ip, conf['ip_pool'])
            single_result = /^(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])$/.match(ip)
            conf['ip_pool'] << ip if (single_result)
          }
        }
        @lock = Mutex.new
      end

      def put_range_to_ip_pool(ip_range, pool)
        range_result = /^(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])-(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])$/.match(ip_range)
        return nil if range_result.nil?
        ip11 = range_result[1].to_i
        ip12 = range_result[2].to_i
        ip13 = range_result[3].to_i
        ip14 = range_result[4].to_i
        ip21 = range_result[5].to_i
        ip22 = range_result[6].to_i
        ip23 = range_result[7].to_i
        ip24 = range_result[8].to_i
        while (ip11 <= ip21)
          while (ip12<=ip22)
            while (ip13<=ip23)
              while (ip14<=ip24)
                pool << "#{ip11}.#{ip12}.#{ip13}.#{ip14}"
                ip14 += 1
              end
              ip13 += 1
            end
            ip12 += 1
          end
          ip11 += 1
        end

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

