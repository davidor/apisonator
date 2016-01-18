require_relative '../storage'
require_relative 'storage'
require_relative 'keys'
require_relative 'info'

module ThreeScale
  module Backend
    module Stats
      module Tasks
        extend Keys

        module_function

        def delete_all_buckets_and_keys_only_as_rake!(options = {})
          Storage.disable!

          Info.pending_buckets.each do |bucket|
            keys = storage.smembers(changed_keys_bucket_key(bucket))
            unless options[:silent] == true
              puts "Deleting bucket: #{bucket}, containing #{keys.size} keys"
            end
            storage.del(changed_keys_bucket_key(bucket))
          end
          storage.del(changed_keys_key)
        end

        private

        def self.storage
          Backend::Storage.instance
        end
      end
    end
  end
end
