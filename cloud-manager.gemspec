# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "cloud-manager"
  s.version = "0.5.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["VMware Serengeti team (Haiyu Wang, Jun Xiao)"]
  s.date = "2012-06-02"
  s.description = "Cloud-manager"
  s.email = "hadoop-bj@vmware.com"
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc"
  ]
  s.files = [
    "Gemfile",
    "LICENSE.txt",
    "README.rdoc",
    "Rakefile",
    "cloud-manager.gemspec",
    "lib/cloud_manager.rb",
    "lib/cloud_manager/client_fog.rb",
    "lib/cloud_manager/cloud_deploy.rb",
    "lib/cloud_manager/cloud_placement.rb",
    "lib/cloud_manager/cluster_diff.rb",
    "lib/cloud_manager/exception.rb",
    "lib/cloud_manager/iaas_result.rb",
    "lib/cloud_manager/network_res.rb",
    "lib/cloud_manager/utils.rb",
    "lib/cloud_manager/client.rb",
    "lib/cloud_manager/cloud_item.rb",
    "lib/cloud_manager/cloud_progress.rb",
    "lib/cloud_manager/cluster.rb",
    "lib/cloud_manager/group.rb",
    "lib/cloud_manager/iaas_task.rb",
    "lib/cloud_manager/placement.rb",
    "lib/cloud_manager/vm_group.rb",
    "lib/cloud_manager/wait_ready.rb",
    "lib/cloud_manager/cloud_create.rb",
    "lib/cloud_manager/cloud_operations.rb",
    "lib/cloud_manager/cloud.rb",
    "lib/cloud_manager/deploy.rb",
    "lib/cloud_manager/iaas_progress.rb",
    "lib/cloud_manager/log.rb",
    "lib/cloud_manager/resources.rb",
    "lib/cloud_manager/vm.rb",
    "spec/cloud_vm_unit_test.rb",
    "spec/config.rb",
    "spec/fog_dummy.rb",
    "spec/ut.dc_def1.yaml",
    "spec/ut.dc_def2.yaml",
    "spec/ut.dc-working.yaml",
    "spec/ut.dc.yaml",
    "spec/ut.test.yaml",
    "spec/ut.vc.yaml",
    "spec/ut.wdc_def.yaml",
    "spec/ut.wdc.yaml"
  ]
  s.homepage = ""
  s.licenses = [""]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.15"
  s.summary = "manage the cloud, easilier"
  s.test_files = [
    "spec/cloud_vm_unit_test.rb",
    "spec/config.rb",
    "spec/fog_dummy.rb",
    "spec/ut.dc_def1.yaml",
    "spec/ut.dc_def2.yaml",
    "spec/ut.dc-working.yaml",
    "spec/ut.dc.yaml",
    "spec/ut.test.yaml",
    "spec/ut.vc.yaml",
    "spec/ut.wdc_def.yaml",
    "spec/ut.wdc.yaml"
  ]

  s.add_dependency(%q<fog>, ["~> 1.3.1.serengeti.1"])

end

