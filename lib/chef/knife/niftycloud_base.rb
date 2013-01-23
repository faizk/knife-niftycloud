#
# Author:: Satoshi Akama (<satoshi.akama@gmail.com>)
# Copyright:: Copyright (c) 2011 Satoshi Akama
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife'

class Chef
  class Knife
    module NiftycloudBase

      # :nodoc:
      # Would prefer to do this in a rational way, but can't be done b/c of
      # Mixlib::CLI's design :(
      def self.included(includer)
        includer.class_eval do

          deps do
            require "NIFTY"
            require 'readline'
            require 'chef/json_compat'
          end

          option :nifty_cloud_access_key,
            :short => "-A ID",
            :long => "--nifty-cloud-access-key KEY",
            :description => "Your Nifty Cloud Access Key ID",
            :proc => Proc.new { |key| Chef::Config[:knife][:nifty_cloud_access_key] = key }

          option :nifty_cloud_secret_key,
            :short => "-K SECRET",
            :long => "--nifty-cloud-secret-key SECRET",
            :description => "Your Nifty Cloud API Secret Key",
            :proc => Proc.new { |key| Chef::Config[:knife][:nifty_cloud_secret_key] = key }
        end
      end

      def connection
        @connection ||= begin
          connection = NIFTY::Cloud::Base.new(
            :access_key => Chef::Config[:knife][:nifty_cloud_access_key],
            :secret_key => Chef::Config[:knife][:nifty_cloud_secret_key]
          )
        end
      end

      def locate_config_value(key)
        key = key.to_sym
        config[key] || Chef::Config[:knife][key]
      end

      def msg_pair(label, value, color=:cyan)
        if value && !value.to_s.empty?
          puts "#{ui.color(label, color)}: #{value}"
        end
      end

      def validate!(keys=[:nifty_cloud_access_key, :nifty_cloud_secret_access_key])
        errors = []

        keys.each do |k|
          pretty_key = k.to_s.gsub(/_/, ' ').gsub(/\w+/){ |w| (w =~ /(ssh)|(aws)/i) ? w.upcase  : w.capitalize }
          if Chef::Config[:knife][k].nil?
            errors << "You did not provide a valid '#{pretty_key}' value."
          end
        end

        if errors.each{|e| ui.error(e)}.any?
          exit 1
        end
      end

    end
  end
end


