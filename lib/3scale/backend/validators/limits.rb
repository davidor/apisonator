module ThreeScale
  module Backend
    module Validators
      class Limits < Base
        def apply
          values = process(status.values, params[:usage])

          if application.usage_limits.all? { |limit| limit.validate(values) }
            succeed!
          else
            fail!(LimitsExceeded.new)
          end
        end

        private

        def process(values, raw_usage)
          if raw_usage
            metrics = Metric.load_all(status.service.id)
            usage   = metrics.process_usage(raw_usage)

            values = filter_metrics(values, usage.keys)
            values = increment(values, usage)
            values
          else
            values
          end
        end

        def filter_metrics(values, metric_ids)
          values.inject({}) do |memo, (period, usage)|
            memo[period] = slice_hash(usage, metric_ids)
            memo
          end
        end

        def increment(values, usage)
          usage.inject(values) do |memo, (metric_id, value)|
            memo.keys.each do |period|
              memo[period][metric_id] ||= 0
              memo[period][metric_id] += value
            end

            memo
          end
        end

        # TODO: Move this to extensions/hash.rb
        def slice_hash(hash, keys)
          keys.inject({}) do |memo, key|
            memo[key] = hash[key] if hash.has_key?(key)
            memo
          end
        end
      end
    end
  end
end