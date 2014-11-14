require_relative '../../spec_helper'

module ThreeScale
  module Backend
    module Transactor
      describe ReportJob do
        include TestHelpers::Sequences

        before { ThreeScale::Backend::Worker.new }

        describe '.perform' do
          let(:service_id)       { 1000 }
          let(:raw_transactions) { [{}] }
          let(:enqueue_time)     { Time.now.to_f }

          context 'when a backend exception is raised' do
            before do
              ReportJob.should_receive(:parse_transactions) {
                raise ThreeScale::Backend::ServiceIdInvalid.new(service_id)
              }
            end

            it 'rescues the exception' do
              expect {
                ReportJob.perform(service_id, raw_transactions, enqueue_time)
              }.to_not raise_error
            end
          end

          context 'when a core exception is raised' do
            before do
              ReportJob.should_receive(:parse_transactions) {
                raise ThreeScale::Core::ServiceRequiresRegisteredUser.new(service_id)
              }
            end

            it 'rescues the exception' do
              expect {
                ReportJob.perform(service_id, raw_transactions, enqueue_time)
              }.to_not raise_error
            end
          end

          context 'when a generic exception is raised' do
            before do
              ReportJob.should_receive(:parse_transactions) {
                raise Exception.new
              }
            end

            it 'raises the exception' do
              expect {
                ReportJob.perform(service_id, raw_transactions, enqueue_time)
              }.to raise_error(Exception)
            end
          end

          context 'log request storage' do
            before do
              ResqueSpec.reset!
              @service_id, @plan_id, @application_id, @metric_id, @metric_id2 =
                (1..5).map{ next_id }
              @log1 = {'code' => '200', 'request' => '/request?bla=bla&',
                       'response' => '<xml>response</xml>'}
              Metric.save(:service_id => @service_id, :id => @metric_id, :name => 'hits')
              Metric.save(:service_id => @service_id, :id => @metric_id2, :name => 'other')
              Application.save(:id         => @application_id,
                               :service_id => @service_id,
                               :state      => :active,
                               :plan_id    => @plan_id)
            end

            it 'is re-queued when necessary' do
              expect(LogRequestJob).to have_queue_size_of(0)

              Transactor::ReportJob.perform(
                @service_id, {'0' => {'app_id' => @application_id, 'usage' => {'hits' => 1, 'other' => 6}, 'log' => @log1}}, Time.now.getutc.to_f)

              expect(LogRequestJob).to have_queue_size_of(1)
            end
          end
        end
      end
    end
  end
end