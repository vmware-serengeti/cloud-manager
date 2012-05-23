module Serengeti
  module CloudManager
    class VHelperCloud
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

