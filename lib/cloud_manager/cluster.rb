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

# @version 0.6.0

module Serengeti
  module CloudManager
    class Cloud
      def Cluster
        Cluster.new(self)
      end

      class Cluster
        def initialize(cloud)
          @cloud = cloud
        end

        SUPPORT_FUNC = ['create', 'update', 'resize', 'delete', 'start', 'stop', 'list']

        def method_missing(m, *args, &block)
          if SUPPORT_FUNC.include?(m)
            return @cloud.send(m, *args)
          end
          super
        end

        def groups()
          Groups.new(@cloud)
        end

        def nodes()
          Nodes.new(@cloud)
        end

      end

    end
  end
end
