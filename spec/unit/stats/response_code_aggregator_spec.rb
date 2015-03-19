require_relative '../../spec_helper'
require_relative '../../../test/test_helpers/fixtures'

module ThreeScale
  module Backend
    module Stats
      include TestHelpers::Fixtures

      describe ResponseCodeAggregator do
        let(:service_id)     { 1000 }
        let(:aggregator) { ResponseCodeAggregator.new }
        let(:transaction) { Transaction.new(service_id: 1000, response_code: 404) }

        describe '.aggregate' do
          it 'returns one set for unknown response_code' do
            transaction.response_code = 499
            expect(aggregator.aggregate(transaction).length).to eq(1)
          end

          it 'returns two sets for known response_code' do
            expect(aggregator.aggregate(transaction).length).to eq(2)
          end

          it 'returns empty for nil response_codes' do
            transaction.response_code = nil
            expect(aggregator.aggregate(transaction).length).to eq(0)
          end

          it 'returns empty for incorrect response_codes' do
            transaction.response_code = Array.new
            expect(aggregator.aggregate(transaction).length).to eq(0)
          end

          it 'returns two sets for known string response_codes' do
            transaction.response_code = "404"
            expect(aggregator.aggregate(transaction).length).to eq(2)
          end

          it 'returns empty for incorrect string response_codes' do
            transaction.response_code = "4xx9"
            expect(aggregator.aggregate(transaction).length).to eq(0)
          end

        end

      end
    end
  end
end
