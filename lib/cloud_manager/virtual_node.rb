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
    # associated vm groups can be put in a Virtual Group
    class VirtualGroup
      attr_accessor :vm_groups

      def initialize(vm_groups)
        @vm_groups = []
        vm_groups.each { | vm_group | @vm_groups << vm_group }
      end

    end

    class VmSpec
      attr_accessor :name
      attr_accessor :group_name
      attr_accessor :spec

      def initialize(vm_group, vm_name)
        @name = vm_name
        @group_name = vm_group.name
        @spec = vm_group.to_spec || {}
      end

      def to_spec
        spec["name"] = @name
        spec
      end

    end

    #vms that needs to be placed on the same host formalize a virtual node
    class VirtualNode
      attr_accessor :vm_specs

      def initialize()
        @vm_specs = []
      end

      def each &blk
        @vm_specs.each &blk
      end

      def map &blk
        @vm_specs.map &blk
      end

      def add (vm_spec)
        @vm_specs << vm_spec
      end

      def to_s
        str = "[ "
        vm_specs.each do |spec|
          str += "[ " + spec.to_s + " ], "
        end
        str += " ]"
      end
    end
  end
end