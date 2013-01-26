#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2010-2011 Opscode, Inc.
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

require 'chef/knife/niftycloud_base'

class Chef
  class Knife
    class NiftycloudServerList < Knife

      include Knife::NiftycloudBase

      banner "knife niftycloud server list (options)"

      option :name,
        :short => "-n",
        :long => "--no-name",
        :boolean => true,
        :default => true,
        :description => "Do not display name tag in output"

      def run
        $stdout.sync = true

        validate!

        server_list = [
          ui.color('Server Name', :bold),
          ui.color('IP Type', :bold),
          ui.color('Global IP', :bold),
          ui.color('Private IP', :bold),
          ui.color('Private DNS Name', :bold),
          ui.color('Instance Type', :bold),
          ui.color('Image', :bold),
          ui.color('SSH Key', :bold),
          ui.color('FireWall', :bold),
          ui.color('State', :bold)
        ]
        output_column_count = server_list.length

        servers = connection.describe_instances()

        set = servers.reservationSet
        if set
          set.item.each do |instance|

            server = instance.instancesSet.item.first
            server_list << server.instanceId
            server_list << server.ipType
            server_list << (server.ipAddress.nil? ? '' : server.ipAddress)
            server_list << (server.privateIpAddress.nil? ? '' : server.privateIpAddress)
            server_list << (server.privateDnsName.nil? ? '' : server.privateDnsName)
            server_list << server.instanceType
            server_list << server.imageId
            server_list << (server.keyName.nil? ? '' : server.keyName)
            server_list << (instance.groupSet.nil? ? '' : instance.groupSet.item.first.groupId)

            server_list << begin
              state = server.instanceState.name
              case state
              when 'stopped'
                ui.color(state, :red)
              when 'pending'
                ui.color(state, :yellow)
              else
                ui.color(state, :green)
              end
            end
          end
          puts ui.list(server_list, :columns_across, output_column_count)
        end
      end
    end
  end
end
