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
      #TODO check cluster difference between existed cluster and wanted
      def cluster_diff(dc_resources, vm_groups_input, vm_groups_existed)
        #TODO add diff code later
        @logger.debug("")
        changes = []

        return [nil, changes]
      end

      ####################################################################
      # Inner functions for cluster diff checking
      def check_cluster_diff(dc_resources, vm_groups_input, vm_groups_existed)
        #TODO add diff checking code later
      end
    end
  end
end

