module ThreeScale
  module Backend
    module Constants
      module All
        TIME_FORMAT          = '%Y-%m-%d %H:%M:%S %z'.freeze
        PIPELINED_SLICE_SIZE = 400
        SLEEP_BETWEEN_SCANS = 0.01 # In seconds
        SCAN_SLICE = 500
      end

      def self.included(base)
        All.constants.each do |k|
          base.const_set(k, All.const_get(k))
          base.private_constant k
        end
      end
    end

    include Constants
  end
end
