#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2009-2011 Opscode, Inc.
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

# These two are needed for the '--purge' deletion case
require 'chef/node'
require 'chef/api_client'

class Chef
  class Knife
    class NiftycloudServerDelete < Knife

      include Knife::NiftycloudBase

      banner "knife niftycloud server delete SERVER [SERVER] (options)"

      attr_reader :server

      option :purge,
        :short => "-P",
        :long => "--purge",
        :boolean => true,
        :default => false,
        :description => "Destroy corresponding node and client on the Chef Server, in addition to destroying the Nifty Cloud node itself.  Assumes node and client have the same name as the server (if not, add the '--node-name' option)."

      option :chef_node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The name of the node and client to delete, if it differs from the server name.  Only has meaning when used with the '--purge' option."

      # Extracted from Chef::Knife.delete_object, because it has a
      # confirmation step built in... By specifying the '--purge'
      # flag (and also explicitly confirming the server destruction!)
      # the user is already making their intent known.  It is not
      # necessary to make them confirm two more times.
      def destroy_item(klass, name, type_name)
        begin
          object = klass.load(name)
          object.destroy
          ui.warn("Deleted #{type_name} #{name}")
        rescue Net::HTTPServerException
          ui.warn("Could not find a #{type_name} named #{name} to delete!")
        end
      end

      def run

        validate!

        @name_args.each do |server_name|
          begin
            @response = connection.describe_instances(:instance_id => server_name)
            @server = @response.reservationSet.item.first.instancesSet.item.first
            @attribute = connection.describe_instance_attribute(:instance_id => server_name,:attribute =>'disableApiTermination')

            msg_pair("Server Name", @server.instanceId)
            msg_pair("IP Type", @server.ipType)
            msg_pair("Global IP Address", (@server.ipAddress.nil? ? '' : @server.ipAddress))
            msg_pair("Private IP Address", (@server.privateIpAddress.nil? ? '' : @server.privateIpAddress))
            msg_pair("Private DNS Name", (@server.privateIpAddress.nil? ? '' : @server.privateIpAddress))
            msg_pair("Instance Type", @server.instanceType)
            msg_pair("Image", @server.imageId)
            msg_pair("SSH Key", (@server.keyName.nil? ? '' : @server.keyName))
            msg_pair("FireWall", (@server.groupSet.nil? ? '' : $server.groupSet.item.first.groupId))
            state = @server.instanceState.name
            msg_pair("State", state)

            puts "\n"
            confirm("Do you really want to delete this server")

            is_not_deletable = @attribute.disableApiTermination.value

            if state != 'stopped'
              connection.stop_instances(:instance_id => @server.instanceId)
              while state != 'stopped'
                puts "."
                @response = connection.describe_instances(:instance_id => @server.instanceId)
                @server = @response.reservationSet.item.first.instancesSet.item.first
                state = @server.instanceState.name
                sleep 5
              end
            elsif is_not_deletable != 'false'
              connection.modify_instance_attribute(:instance_id => @server.instanceId, :attribute => 'disableApiTermination', :value => 'false')
              while is_not_deletable != 'false'
                puts "."
                @attribute = connection.describe_instance_attribute(:instance_id => @server.instanceId,:attribute =>'disableApiTermination')
                is_not_deletable = @attribute.disableApiTermination.value
                sleep 5
              end
            end

            connection.terminate_instances(:instance_id => @server.instanceId)

            ui.warn("Deleted server #{@server.instanceId}")

            if config[:purge]
              thing_to_delete = config[:chef_node_name] || server_name
              destroy_item(Chef::Node, thing_to_delete, "node")
              destroy_item(Chef::ApiClient, thing_to_delete, "client")
            else
              ui.warn("Corresponding node and client for the #{@server.instanceId} server were not deleted and remain registered with the Chef Server")
            end
          rescue NoMethodError
            ui.error("Could not locate server '#{@server.instanceId}'.  Please verify it was provisioned in the availability_zone(EAST/WEST).")
          end
        end
      end

    end
  end
end


