# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "knife-niftycloud/version"

Gem::Specification.new do |s|
  s.name        = "knife-niftycloud"
  s.version     = Knife::Niftycloud::VERSION
  s.has_rdoc = true
  s.authors     = ["Satoshi Akama"]
  s.email       = ["satoshi.akama@gmail.com"]
  s.homepage = "http://github.com/knife-niftycloud/"
  s.summary = "Nifty Cloud Support for Chef's Knife Command"
  s.description = s.summary
  s.extra_rdoc_files = ["README.rdoc", "LICENSE" ]

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.add_dependency "chef", ">= 0.10.6"
  s.add_dependency "nifty-cloud-sdk", ">= 1.7"
  %w(rspec-core rspec-expectations rspec-mocks  rspec_junit_formatter).each { |gem| s.add_development_dependency gem }

  s.require_paths = ["lib"]
end
