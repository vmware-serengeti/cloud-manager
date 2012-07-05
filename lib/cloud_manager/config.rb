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

# @since serengeti 0.5.1
# @version 0.5.1

module Serengeti
  module CloudManager
    @@self_config = nil
    def self.config
      @@self_config = Serengeti::CloudManager::Config.new if @@self_config.nil?
      @@self_config
    end

    class BaseObject
      def logger
        Serengeti::CloudManager.logger
      end

      def config
        Serengeti::CloudManager.config 
      end

end

    class Config
      def self.def_const_value(name, value)
        define_method("#{name}") do
          @lock.synchronize { (@config["#{name.to_s}"].nil?) ? value : @config["#{name.to_s}"] }
        end
        define_method("#{name}=") do |arg|
          @lock.synchronize { @config["#{name.to_s}"] = arg }
        end
      end

      def initialize(input = nil)
        @config = {}
        @lock = Mutex.new
        update(input) if input
      end

      def method_missing(m, *args, &block)
        v = @config[m.to_s]
        super if v.nil?
        v
      end

      def update(input)
        return if input.nil?
        @lock.synchronize do
          input.each { |name, value| @config["#{name.to_s}"] = value }
          @config.merge(input)
        end
      end
    end

  end
end
