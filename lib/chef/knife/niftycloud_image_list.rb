#
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
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
    class NiftycloudImageList < Knife

      include Knife::NiftycloudBase

      banner "knife niftycloud image list (options)"

      def run

        validate!

        image_list = [
          ui.color('Image Id', :bold),
          ui.color('Architecture', :bold),
          ui.color('Owner', :bold),
          ui.color('isPublic', :bold),
          ui.color('Name', :bold)
        ]
        output_column_count = image_list.length

        connection.describe_images.imagesSet.item.each do |image|
          image_list << image.imageId
          image_list << image.architecture
          image_list << "#{image.imageOwnerId}"
          image_list << (image.isPublic ? 'public' : 'private')
          image_list << image.name
        end
        puts ui.list(image_list, :columns_across, output_column_count)
      end
    end
  end
end
