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

require 'logger'
module Serengeti
  module CloudManager

    LOG_LEVEL = {'debug'=>Logger::DEBUG, 'info'=>Logger::INFO, 'warning'=>Logger::WARN, 'error' => Logger::ERROR}
    LOG_LEVEL_NAME = LOG_LEVEL.invert

    class SerengetiLogger < Logger
      @@level = LOG_LEVEL['debug']
      def self.set_log_level(log_level)
        @@level = log_level
      end

      def initialize(options={})
        @level = options[:level] || @@level || LOG_LEVEL['debug']
        log_file = options[:file] || STDOUT
        @logger = Logger.new(log_file)
        @logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.rfc2822}] #{severity}: #{msg}\n"
        end
        @logger.level = @level
        @logger.debug("initiated logger with level #{LOG_LEVEL_NAME[@level]} and output to #{log_file.class}")
      end

      def info(msg)
        @logger.info(msg2str(msg))
      end

      def fatal(msg)
        @logger.fatal(msg2str(msg))
      end

      def warn(msg)
        @logger.warn(msg2str(msg))
      end

      def debug(msg)
        @logger.debug(msg2str(msg))
      end

      def error(msg)
        @logger.error(msg2str(msg))
      end

      def inspect; "<Cloud-manager-Logger>" end

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

    class Cloud
      @@self_logger = nil
      def self.Logger
        @@self_logger = SerengetiLogger.new if @@self_logger.nil?
        @@self_logger
      end

      def self.set_log_level(log_level)
        log_level = log_level.to_s.downcase
        raise "Unknown log level #{log_level}, it should be in #{LOG_LEVEL.keys}" unless LOG_LEVEL.has_key?(log_level)
        SerengetiLogger.set_log_level (LOG_LEVEL[log_level])
      end
    end
  end

end
