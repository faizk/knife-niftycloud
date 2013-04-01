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
    class NiftycloudServerCreate < Knife

      include Knife::NiftycloudBase

      deps do
        require 'NIFTY'
        require 'readline'
        require 'chef/json_compat'
        require 'chef/knife/bootstrap'
        Chef::Knife::Bootstrap.load_deps
      end

      banner "knife niftycloud server create (options)"

      attr_accessor :initial_sleep_delay
      attr_reader :server

      option :instance_type,
        :short => "-it INSTANCE_TYPE",
        :long => "--instance-type INSTANCE_TYPE",
        :description => "The Instance Type of server (small2, medium4, etc)",
        :proc => Proc.new { |it| Chef::Config[:knife][:instance_type] = it }

      option :image_id,
        :short => "-im IMAGE_ID",
        :long => "--image-id IMAGE_ID",
        :description => "The Image ID of server(14, 21, etc)"

      option :firewall,
        :short => "-f FIREWALL",
        :long => "--firewall X,Y,Z",
        :description => "The firewall for this server"

      option :chef_node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The Chef node name for your new node",
        :proc => Proc.new { |key| Chef::Config[:knife][:chef_node_name] = key }

      option :ssh_key_name,
        :short => "-S KEY",
        :long => "--ssh-key KEY",
        :description => "The Nifty Cloud SSH key name",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_key_name] = key }

      option :ssh_user,
        :short => "-x USERNAME",
        :long => "--ssh-user USERNAME",
        :description => "The ssh username",
        :default => "root"

      option :ssh_password,
        :short => "-P PASSWORD",
        :long => "--ssh-password PASSWORD",
        :description => "The ssh password"

      option :ssh_passphrase,
        :short => "-R PASSPHRASE",
        :long => "--ssh-passphrase PASSPHRASE",
        :description => "The ssh passphrase",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_passphrase] = key }

      option :identity_file,
        :short => "-i IDENTITY_FILE",
        :long => "--identity-file IDENTITY_FILE",
        :description => "The SSH identity file used for authentication"

      option :accounting_type,
        :short => "-AT ACCOUNTING_TYPE",
        :long => "--accounting-type ACCOUNTING_TYPE",
        :description => "The Nifty Cloud ACCOUNTING_TYPE(monthly=1, cap=2)",
        :proc => Proc.new { |at| Chef::Config[:knife][:accounting_type] = at }

      option :ip_type,
        :short => "-IP IP_TYPE",
        :long => "--ip-type IP_TYPE",
        :description => "The Nifty Cloud IP_TYPE(static,dynamic)"

      option :prerelease,
        :long => "--prerelease",
        :description => "Install the pre-release chef gems"

      option :bootstrap_version,
        :long => "--bootstrap-version VERSION",
        :description => "The version of Chef to install",
        :proc => Proc.new { |v| Chef::Config[:knife][:bootstrap_version] = v }

      option :distro,
        :short => "-d DISTRO",
        :long => "--distro DISTRO",
        :description => "Bootstrap a distro using a template; default is 'chef-full'",
        :proc => Proc.new { |d| Chef::Config[:knife][:distro] = d }

      option :template_file,
        :long => "--template-file TEMPLATE",
        :description => "Full path to location of template to use",
        :proc => Proc.new { |t| Chef::Config[:knife][:template_file] = t },
        :default => false

      option :run_list,
        :short => "-r RUN_LIST",
        :long => "--run-list RUN_LIST",
        :description => "Comma separated list of roles/recipes to apply",
        :proc => lambda { |o| o.split(/[\s,]+/) }

      option :json_attributes,
        :short => "-j JSON",
        :long => "--json-attributes JSON",
        :description => "A JSON string to be added to the first run of chef-client",
        :proc => lambda { |o| JSON.parse(o) }

      option :host_key_verify,
        :long => "--[no-]host-key-verify",
        :description => "Verify host key, enabled by default.",
        :boolean => true,
        :default => true

      option :hint,
        :long => "--hint HINT_NAME[=HINT_FILE]",
        :description => "Specify Ohai Hint to be set on the bootstrap target.  Use multiple --hint options to specify multiple hints.",
        :proc => Proc.new { |h|
           Chef::Config[:knife][:hints] ||= {}
           name, path = h.split("=")
           Chef::Config[:knife][:hints][name] = path ? JSON.parse(::File.read(path)) : Hash.new
        }

      def tcp_test_ssh(hostname)
        tcp_socket = TCPSocket.new(hostname, 22)
        readable = IO.select([tcp_socket], nil, nil, 5)
        if readable
          Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
          yield
          true
        else
          false
        end
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, IOError
        sleep 2
        false
      rescue Errno::EPERM, Errno::ETIMEDOUT
        false
      ensure
        tcp_socket && tcp_socket.close
      end

      def run
        $stdout.sync = true

        validate!

        @response = connection.run_instances(create_server_def)
        @server = @response.instancesSet.item.first
        state = @server.instanceState.name
        while state != 'running'
          puts "."
          @response = connection.describe_instances(:instance_id => locate_config_value(:chef_node_name))
          @server = @response.reservationSet.item.first.instancesSet.item.first
          state = @server.instanceState.name
          sleep 5
        end

        msg_pair("Server Name", @server.instanceId)
        msg_pair("Instance Type", @server.instanceType)
        msg_pair("Image", @server.imageId)
        msg_pair("FireWall", (@server.groupSet.nil? ? '' : @server.groupSet.item.first.groupId))
        msg_pair("SSH Key", @server.keyName)

        print "\n#{ui.color("Waiting for server", :magenta)}"

        # wait for it to be ready to do stuff
        @server.wait_for { print "."; ready? }

        puts("\n")

        msg_pair("Private DNS Name", @server.privateDnsName)
        msg_pair("Global IP Address", @server.ipAddress)
        msg_pair("Private IP Address", @server.privateIpAddress)

        ssh_ip_address = config[:ssh_locally] ? @server.privateIpAddress : @server.ipAddress

        print "\n#{ui.color("Waiting for sshd", :magenta)}"

        print(".") until tcp_test_ssh(ssh_ip_address) {
          sleep @initial_sleep_delay ||= 10
          puts("done")
        }

        bootstrap_for_node(@server,ssh_ip_address).run

        puts "\n"
        msg_pair("Server Name", @server.instanceId)
        msg_pair("Instance Type", @server.instanceType)
        msg_pair("Image", @server.imageId)
        msg_pair("Firewall", (@server.groupSet.nil? ? '' : $server.groupSet.item.first.groupId))
        msg_pair("SSH Key", @server.key_name)
        msg_pair("Global IP Address", @server.ipAddress)
        msg_pair("Private IP Address", @server.privateIpAddress)
        msg_pair("Environment", config[:environment] || '_default')
        msg_pair("Run List", (config[:run_list] || []).join(', '))
        msg_pair("JSON Attributes",config[:json_attributes]) unless !config[:json_attributes] || config[:json_attributes].empty?
      end

      def bootstrap_for_node(server,ssh_host)
        bootstrap = Chef::Knife::Bootstrap.new
        bootstrap.name_args = [ssh_host]
        bootstrap.config[:run_list] = locate_config_value(:run_list) || []
        bootstrap.config[:ssh_user] = config[:ssh_user]
        bootstrap.config[:ssh_password] = config[:ssh_password]
        bootstrap.config[:ssh_passphrase] = config[:ssh_passphrase]
        bootstrap.config[:ssh_port] = config[:ssh_port]
        bootstrap.config[:ssh_gateway] = config[:ssh_gateway]
        bootstrap.config[:identity_file] = config[:identity_file]
        bootstrap.config[:chef_node_name] = locate_config_value(:chef_node_name) || server.instanceId
        bootstrap.config[:prerelease] = config[:prerelease]
        bootstrap.config[:bootstrap_version] = locate_config_value(:bootstrap_version)
        bootstrap.config[:first_boot_attributes] = locate_config_value(:json_attributes) || {}
        case server.imageId
        when 1..14
          distro = 'centos5-gems'
        when 17
          distro = 'centos5-gems'
        when 21
          distro = 'centos5-gems'
        else
          distro = 'centos5-gems'
        end
        bootstrap.config[:distro] = distro
        bootstrap.config[:use_sudo] = false
        bootstrap.config[:template_file] = locate_config_value(:template_file)
        bootstrap.config[:environment] = config[:environment]
        # Modify global configuration state to ensure hint gets set by
        # knife-bootstrap
        Chef::Config[:knife][:hints] ||= {}
        Chef::Config[:knife][:hints]["nifty-cloud"] ||= {}
        bootstrap
      end

      def image
        @image ||= connection.describe_images(:image_id => locate_config_value(:image_id))
      end

      def validate!

        super([:ssh_key_name, :nifty_cloud_access_key, :nifty_cloud_secret_key])

        if image.nil?
          ui.error("You have not provided a valid image value.  Please note the short option for this value recently changed from '-i' to '-I'.")
          exit 1
        end
      end

      def create_server_def
        server_def = {
          :image_id => locate_config_value(:image_id),
          :key_name => Chef::Config[:knife][:ssh_key_name],
          :security_group => locate_config_value(:firewall),
          :instance_type => locate_config_value(:instance_type),
          :disable_api_termination => false,
          :accounting_type => locate_config_value(:accounting_type),
          :instance_id => locate_config_value(:chef_node_name),
          :admin       => locate_config_value(:ssh_user),
          :password    => locate_config_value(:ssh_password),
          :ip_type     => locate_config_value(:ip_type)
        }
        server_def
      end
    end
  end
end
