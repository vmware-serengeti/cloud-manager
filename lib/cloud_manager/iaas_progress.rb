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

module Serengeti
  module CloudManager
    class IaasProcess
      attr_accessor :cluster_name
      attr_accessor :progress
      attr_accessor :result
      attr_accessor :finished
      attr_accessor :status
      def initialize
        @progress = 0
        @finished = false
        @status = "birth"
        @result = ""
      end
      def finished? ;@finished end
      def inspect
        "#{@progress}%, finished ? #{@finished?'yes':'no'}, status:#{@status}, servers:\n#{result.inspect}"
      end
    end
  end
end
