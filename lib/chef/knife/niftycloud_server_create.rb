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
        :short => "-it instance_type",
        :long => "--instance-type INSTANCE_TYPE",
        :description => "The Instance Type of server (small2, medium4, etc)",
        :proc => Proc.new { |f| Chef::Config[:knife][:instance-type] = it }

      option :image,
        :short => "-I IMAGE",
        :long => "--image IMAGE",
        :description => "The VM Image for the server",
        :proc => Proc.new { |i| Chef::Config[:knife][:image] = i }

      option :firewall,
        :short => "-F X,Y,Z",
        :long => "--firewall X,Y,Z",
        :description => "The firewall for this server",
        :proc => Proc.new { |groups| groups.split(',') }

      option :chef_node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The Chef node name for your new node",
        :proc => Proc.new { |key| Chef::Config[:knife][:chef_node_name] = key }

      option :ssh_key_name,
        :short => "-S KEY",
        :long => "--ssh-key KEY",
        :description => "The AWS SSH key id",
        :proc => Proc.new { |key| Chef::Config[:knife][:aws_ssh_key_id] = key }

      option :ssh_user,
        :short => "-x USERNAME",
        :long => "--ssh-user USERNAME",
        :description => "The ssh username",
        :default => "root"

      option :ssh_password,
        :short => "-P PASSWORD",
        :long => "--ssh-password PASSWORD",
        :description => "The ssh password"

      option :ssh_port,
        :short => "-p PORT",
        :long => "--ssh-port PORT",
        :description => "The ssh port",
        :default => "22",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_port] = key }

      option :ssh_gateway,
        :short => "-w GATEWAY",
        :long => "--ssh-gateway GATEWAY",
        :description => "The ssh gateway server",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_gateway] = key }


      option :identity_file,
        :short => "-i IDENTITY_FILE",
        :long => "--identity-file IDENTITY_FILE",
        :description => "The SSH identity file used for authentication"

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

      option :disk_size,
        :long => "--disk-size SIZE",
        :description => "The size of the Extra Disk volume in GB"

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

      option :subnet_id,
        :short => "-s SUBNET-ID",
        :long => "--subnet SUBNET-ID",
        :description => "create node in this Virtual Private Cloud Subnet ID (implies VPC mode)",
        :proc => Proc.new { |key| Chef::Config[:knife][:subnet_id] = key }

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

      option :ephemeral,
        :long => "--ephemeral EPHEMERAL_DEVICES",
        :description => "Comma separated list of device locations (eg - /dev/sdb) to map ephemeral devices",
        :proc => lambda { |o| o.split(/[\s,]+/) },
        :default => []

      def tcp_test_ssh(hostname, ssh_port)
        tcp_socket = TCPSocket.new(hostname, ssh_port)
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

        @server = connection.servers.create(create_server_def)

        hashed_tags={}
        tags.map{ |t| key,val=t.split('='); hashed_tags[key]=val} unless tags.nil?

        # Always set the Name tag
        unless hashed_tags.keys.include? "Name"
          hashed_tags["Name"] = locate_config_value(:chef_node_name) || @server.id
        end

        hashed_tags.each_pair do |key,val|
          connection.tags.create :key => key, :value => val, :resource_id => @server.id
        end

        msg_pair("Server Name", @server.name)
        msg_pair("Instance Type", @server.instance_type)
        msg_pair("Image", @server.image_id)

        # If we don't specify a security group or security group id, Fog will
        # pick the appropriate default one. In case of a VPC we don't know the
        # default security group id at this point unless we look it up, hence
        # 'default' is printed if no id was specified.
        printed_security_groups = "default"
        printed_security_groups = @server.groups.join(", ") if @server.groups
        msg_pair("FireWall", printed_firewall) unless vpc_mode? or (@server.groups.nil)

        printed_security_group_ids = "default"

        msg_pair("SSH Key", @server.key_name)

        print "\n#{ui.color("Waiting for server", :magenta)}"

        # wait for it to be ready to do stuff
        @server.wait_for { print "."; ready? }

        puts("\n")

        msg_pair("Public DNS Name", @server.dns_name)
        msg_pair("Global IP Address", @server.public_ip_address)

        msg_pair("Private IP Address", @server.private_ip_address)

        print "\n#{ui.color("Waiting for sshd", :magenta)}"

        wait_for_sshd(ssh_connect_host)

        bootstrap_for_node(@server,ssh_connect_host).run

        puts "\n"
        msg_pair("Server Name", @server.name)
        msg_pair("Instance Type", @server.instance_type)
        msg_pair("Image", @server.image_id)
        msg_pair("Firewall", printed_security_groups) unless vpc_mode? or (@server.groups.nil? and @server.security_group_ids)
        msg_pair("SSH Key", @server.key_name)

        msg_pair("Global IP Address", @server.public_ip_address)

        msg_pair("Private IP Address", @server.private_ip_address)
        msg_pair("Environment", config[:environment] || '_default')
        msg_pair("Run List", (config[:run_list] || []).join(', '))
        msg_pair("JSON Attributes",config[:json_attributes]) unless !config[:json_attributes] || config[:json_attributes].empty?
      end

      def bootstrap_for_node(server,ssh_host)
        bootstrap = Chef::Knife::Bootstrap.new
        bootstrap.name_args = [ssh_host]
        bootstrap.config[:run_list] = locate_config_value(:run_list) || []
        bootstrap.config[:ssh_user] = config[:ssh_user]
        bootstrap.config[:ssh_port] = config[:ssh_port]
        bootstrap.config[:ssh_gateway] = config[:ssh_gateway]
        bootstrap.config[:identity_file] = config[:identity_file]
        bootstrap.config[:chef_node_name] = locate_config_value(:chef_node_name) || server.id
        bootstrap.config[:prerelease] = config[:prerelease]
        bootstrap.config[:bootstrap_version] = locate_config_value(:bootstrap_version)
        bootstrap.config[:first_boot_attributes] = locate_config_value(:json_attributes) || {}
        bootstrap.config[:distro] = locate_config_value(:distro) || "chef-full"
        bootstrap.config[:use_sudo] = true unless config[:ssh_user] == 'root'
        bootstrap.config[:template_file] = locate_config_value(:template_file)
        bootstrap.config[:environment] = config[:environment]
        # Modify global configuration state to ensure hint gets set by
        # knife-bootstrap
        Chef::Config[:knife][:hints] ||= {}
        Chef::Config[:knife][:hints]["nifty-cloud"] ||= {}
        bootstrap
      end

      def ami
        @ami ||= connection.images.get(locate_config_value(:image))
      end

      def validate!

        super([:image, :aws_ssh_key_id, :aws_access_key_id, :aws_secret_access_key])

        if ami.nil?
          ui.error("You have not provided a valid image (AMI) value.  Please note the short option for this value recently changed from '-i' to '-I'.")
          exit 1
        end

        if vpc_mode? and !!config[:security_groups]
          ui.error("You are using a VPC, security groups specified with '-G' are not allowed, specify one or more security group ids with '-g' instead.")
          exit 1
        end

      end

      def create_server_def
        server_def = {
          :image_id => locate_config_value(:image),
          :groups => config[:security_groups],
          :flavor_id => locate_config_value(:flavor),
          :key_name => Chef::Config[:knife][:aws_ssh_key_id],
          :availability_zone => locate_config_value(:availability_zone)
        }
        server_def[:subnet_id] = locate_config_value(:subnet_id) if vpc_mode?

        if Chef::Config[:knife][:aws_user_data]
          begin
            server_def.merge!(:user_data => File.read(Chef::Config[:knife][:aws_user_data]))
          rescue
            ui.warn("Cannot read #{Chef::Config[:knife][:aws_user_data]}: #{$!.inspect}. Ignoring option.")
          end
        end
      end

      def wait_for_sshd(hostname)
        config[:ssh_gateway] ? wait_for_tunnelled_sshd(hostname) : wait_for_direct_sshd(hostname, config[:ssh_port])
      end

      def wait_for_tunnelled_sshd(hostname)
        print(".")
        print(".") until tunnel_test_ssh(ssh_connect_host) {
          sleep @initial_sleep_delay ||= (vpc_mode? ? 40 : 10)
          puts("done")
        }
      end

      def tunnel_test_ssh(hostname, &block)
        gw_host, gw_user = config[:ssh_gateway].split('@').reverse
        gw_host, gw_port = gw_host.split(':')
        gateway = Net::SSH::Gateway.new(gw_host, gw_user, :port => gw_port || 22)
        status = false
        gateway.open(hostname, config[:ssh_port]) do |local_tunnel_port|
          status = tcp_test_ssh('localhost', local_tunnel_port, &block)
        end
        status
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, IOError
        sleep 2
        false
      rescue Errno::EPERM, Errno::ETIMEDOUT
        false
      end

      def wait_for_direct_sshd(hostname, ssh_port)
        print(".") until tcp_test_ssh(ssh_connect_host, ssh_port) {
          sleep @initial_sleep_delay ||= (vpc_mode? ? 40 : 10)
          puts("done")
        }
      end

      def ssh_connect_host
        @ssh_connect_host ||= if config[:server_connect_attribute]
          server.send(config[:server_connect_attribute])
        else
          vpc_mode? ? server.private_ip_address : server.dns_name
        end
      end
    end
  end
end
