require_relative '../spec_helper'
require_relative '../../lib/3scale/backend/aggregator/stats_info'

module ThreeScale
  module Backend
    module Aggregator
      describe StatsInfo do
        def storage
          ThreeScale::Backend::Storage.instance
        end

        describe '#pending_buckets' do
          subject { StatsInfo.pending_buckets }

          context 'without pending buckets' do
            it { expect(subject).to be_empty }
          end

          context 'with pending buckets' do
            before do
              storage.zadd(StatsKeys.changed_keys_key, 0, "foo")
              storage.zadd(StatsKeys.changed_keys_key, 1, "bar")
            end

            it { expect(subject).to eql(["foo", "bar"]) }
          end
        end

        describe '#pending_buckets_size' do
          subject { StatsInfo.pending_buckets_size }

          context 'without pending buckets' do
            it { expect(subject).to be(0) }
          end

          context 'with pending buckets' do
            before do
              storage.zadd(StatsKeys.changed_keys_key, 0, "foo")
              storage.zadd(StatsKeys.changed_keys_key, 1, "bar")
            end

            it { expect(subject).to be(2) }
          end
        end

        describe '#pending_keys_by_bucket' do
          subject { StatsInfo.pending_keys_by_bucket }

          context 'without pending buckets' do
            it { expect(subject).to be_empty }
            it { expect(subject).to be_kind_of Hash }
          end

          context 'with pending buckets' do
            before do
              storage.zadd(StatsKeys.changed_keys_key, 0, "foo")
              storage.sadd(StatsKeys.changed_keys_bucket_key("foo"), "20100101")
              storage.sadd(StatsKeys.changed_keys_bucket_key("foo"), "20140404")
            end

            it { expect(subject).to include("foo" => 2) }
          end
        end

        describe '#get_old_buckets_to_process' do
          context "without pending buckets" do
            subject { StatsInfo.get_old_buckets_to_process }
            it { expect(subject).to be_empty }
          end

          context "with pending buckets" do
            before do
              storage.zadd(StatsKeys.changed_keys_key, 0, "foo")
              storage.zadd(StatsKeys.changed_keys_key, 1, "bar")
              storage.zadd(StatsKeys.changed_keys_key, 2, "foobar")
            end

            context "when passes a normal bucket" do
              subject { StatsInfo.get_old_buckets_to_process("bar:2") }
              it { expect(subject).to eql(["foo", "bar"]) }
            end

            context "when passes a special bucket inf" do
              subject { StatsInfo.get_old_buckets_to_process("inf") }
              it { expect(subject).to eql(["foo", "bar", "foobar"])}
            end
          end
        end

        describe '#failed_buckets' do
          subject { StatsInfo.failed_buckets }

          context 'without failed buckets' do
            it { expect(subject).to be_empty }
          end

          context 'with failed buckets' do
            before do
              storage.sadd(StatsKeys.failed_save_to_storage_stats_key, "foo")
              storage.sadd(StatsKeys.failed_save_to_storage_stats_key, "bar")
            end

            it { expect(subject).to include("foo", "bar") }
          end
        end

        describe '#failed_buckets_at_least_once' do
          subject { StatsInfo.failed_buckets_at_least_once }

          context 'without failed buckets' do
            it { expect(subject).to be_empty }
          end

          context 'with failed buckets' do
            before do
              storage.sadd(StatsKeys.failed_save_to_storage_stats_at_least_once_key, "foo")
              storage.sadd(StatsKeys.failed_save_to_storage_stats_at_least_once_key, "bar")
            end

            it { expect(subject).to include("foo", "bar") }
          end
        end

      end
    end
  end
end