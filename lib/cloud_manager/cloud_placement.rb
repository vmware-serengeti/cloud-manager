module VHelper::CloudManager
  class VHelperCloud
    def cluster_placement(dc_resource, vm_groups_input, vm_groups_existed)
      vm_placement = [[]]
      #TODO add placement logical here

      if vm_groups_existed.size > 0
        #TODO add changed placement logical
      end
      
      vm_groups_input.each 

      vm_placement
    end
  end
end
