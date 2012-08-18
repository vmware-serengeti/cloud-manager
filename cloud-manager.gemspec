# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "cloud-manager"
  s.version = "0.6.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["VMware Serengeti team (Haiyu Wang, Jun Xiao)"]
  s.date = "2012-06-02"
  s.description = "Cloud-manager"
  s.email = "hadoop-bj@vmware.com"
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.files = [
    "Gemfile",
    "LICENSE",
    "CHANGELOG.md",
    "README.rdoc",
    "Rakefile",
    "cloud-manager.gemspec",
    "lib/cloud_manager.rb",
    "lib/cloud_manager/cloud.rb",
    "lib/cloud_manager/cloud_create.rb",
    "lib/cloud_manager/cloud_deploy.rb",
    "lib/cloud_manager/cloud_operations.rb",
    "lib/cloud_manager/cloud_progress.rb",
    "lib/cloud_manager/cluster.rb",
    "lib/cloud_manager/config.rb",
    "lib/cloud_manager/deploy.rb",
    "lib/cloud_manager/exception.rb",
    "lib/cloud_manager/group.rb",
    "lib/cloud_manager/iaas_progress.rb",
    "lib/cloud_manager/iaas_result.rb",
    "lib/cloud_manager/iaas_task.rb",
    "lib/cloud_manager/log.rb",
    "lib/cloud_manager/network_res.rb",
    "lib/cloud_manager/placement.rb",
    "lib/cloud_manager/placement_impl.rb",
    "lib/cloud_manager/placement_service.rb",
    "lib/cloud_manager/resource_service.rb",
    "lib/cloud_manager/resources.rb",
    "lib/cloud_manager/utils.rb",
    "lib/cloud_manager/virtual_node.rb",
    "lib/cloud_manager/vm.rb",
    "lib/cloud_manager/vm_group.rb",
    "lib/cloud_manager/wait_ready.rb",
    "lib/plugin/client_fog.rb",
    "lib/plugin/fog_dummy.rb",
    "lib/plugin/placement_rr.rb",
    "lib/plugin/resource_compute.rb",
    "lib/plugin/resource_ft.rb",
    "lib/plugin/resource_ha.rb",
    "lib/plugin/resource_network.rb",
    "lib/plugin/resource_rp.rb",
    "lib/plugin/resource_storage.rb",
    "spec/cloud_unit_test.rb",
    "spec/cloud_func_test.rb",
    "spec/spec_helper.rb",
    "spec/config.rb",
    "spec/unit/placement_spec.rb",
    "spec/assets/unit/ut.cluster_def1.yaml",
    "spec/assets/unit/ut.cluster_def2.yaml",
    "spec/assets/unit/ut.dc.yaml",
    "spec/assets/unit/ut.vc.yaml",
    "spec/assets/unit/placement_constraint_groups.yaml"
  ]
  s.homepage = ""
  s.licenses = [""]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.15"
  s.summary = "manage the cloud, easilier"
  s.test_files = [
    "spec/cloud_unit_test.rb",
    "spec/cloud_func_test.rb",
    "spec/unit/placement_spec.rb",
    "spec/spec_helper.rb",
    "spec/config.rb",
    "spec/assets/unit/ut.cluster_def1.yaml",
    "spec/assets/unit/ut.cluster_def2.yaml",
    "spec/assets/unit/ut.dc.yaml",
    "spec/assets/unit/ut.vc.yaml",
    "spec/assets/unit/placement_constraint_groups.yaml"
  ]

  s.add_dependency(%q<fog>, ["~> 1.3.1.serengeti.1"])
  s.add_dependency(%q<json>, ["~> 1.5.4"])

end

