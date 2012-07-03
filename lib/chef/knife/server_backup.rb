#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
# Copyright:: Copyright (c) 2012 Fletcher Nichol
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
require 'chef/node'
require 'fileutils'
require 'uri'

class Chef
  class Knife
    class ServerBackup < Knife

      banner "knife server backup COMPONENT[ COMPONENT ...] (options)"

      option :backup_dir,
        :short => "-D DIR",
        :long => "--backup-dir DIR",
        :description => "The directory to host backup files"

      def run
        name_args.each { |component| backup_component(component) }
      end

      def backup_dir
        @backup_dir ||= config[:backup_dir] || begin
          server_host = URI.parse(Chef::Config[:chef_server_url]).host
          time = Time.now.utc.strftime("%Y%m%dT%H%M%S.%L-0000")
          base_dir = config[:backup_dir] || Chef::Config[:file_backup_path]

          ::File.join(base_dir, "#{server_host}_#{time}")
        end
      end

      private

      COMPONENTS = {
        "nodes" => { :singular => "node", :klass => Chef::Node },
        "roles" => { :singular => "role", :klass => Chef::Role },
        "environments" => { :singular => "environment", :klass => Chef::Environment },
      }

      def backup_component(component)
        c = COMPONENTS[component]
        dir_path = ::File.join(backup_dir, component)
        ui.msg "Creating #{c[:singular]} backups in #{dir_path}"
        FileUtils.mkdir_p(dir_path)

        Array(c[:klass].list).each do |name, url|
          obj = c[:klass].load(name)
          ui.msg "Backing up #{c[:singular]}[#{name}]"
          ::File.open(::File.join(dir_path, "#{name}.json"), "wb") do |f|
            f.write(obj.to_json)
          end
        end
      end
    end
  end
end
