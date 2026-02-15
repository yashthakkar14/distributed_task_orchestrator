require 'rails_helper'

RSpec.describe ConcurrencyGuardService do
  let(:client) { create(:client, concurrency_limit: 2) }

  describe '.acquire_and_start!' do
    context 'when slots are available' do
      it 'starts the job and returns true' do
        job = create(:job, client: client, status: :queued)
        result = described_class.acquire_and_start!(job, worker_id: 'worker_1')

        expect(result).to be true
        expect(job.reload.running?).to be true
        expect(job.locked_by).to eq('worker_1')
      end

      it 'allows up to concurrency_limit jobs to run' do
        jobs = 2.times.map { create(:job, client: client, status: :queued) }

        jobs.each_with_index do |job, i|
          result = described_class.acquire_and_start!(job, worker_id: "worker_#{i}")
          expect(result).to be true
        end

        expect(Job.where(client_id: client.id, status: :running).count).to eq(2)
      end
    end

    context 'when concurrency limit is reached' do
      before do
        # Fill up all slots
        2.times do |i|
          job = create(:job, client: client, status: :queued)
          described_class.acquire_and_start!(job, worker_id: "worker_#{i}")
        end
      end

      it 'returns false and does not start the job' do
        blocked_job = create(:job, client: client, status: :queued)
        result = described_class.acquire_and_start!(blocked_job, worker_id: 'worker_3')

        expect(result).to be false
        expect(blocked_job.reload.queued?).to be true
      end
    end

    context 'when a slot frees up (job completes)' do
      it 'allows a new job to start' do
        # Fill slots
        first_job = create(:job, client: client, status: :queued)
        second_job = create(:job, client: client, status: :queued)
        described_class.acquire_and_start!(first_job, worker_id: 'w1')
        described_class.acquire_and_start!(second_job, worker_id: 'w2')

        # Third job is blocked
        third_job = create(:job, client: client, status: :queued)
        expect(described_class.acquire_and_start!(third_job, worker_id: 'w3')).to be false

        # Complete the first job (frees a slot)
        first_job.reload.complete!

        # Now the third job can start
        expect(described_class.acquire_and_start!(third_job, worker_id: 'w3')).to be true
        expect(third_job.reload.running?).to be true
      end
    end

    context 'dynamic quota updates' do
      it 'respects lowered concurrency_limit immediately' do
        # Start one job (limit is 2)
        first_job = create(:job, client: client, status: :queued)
        described_class.acquire_and_start!(first_job, worker_id: 'w1')

        # Admin lowers the limit to 1
        client.update!(concurrency_limit: 1)

        # Second job should be blocked (1 running >= new limit of 1)
        second_job = create(:job, client: client, status: :queued)
        result = described_class.acquire_and_start!(second_job, worker_id: 'w2')
        expect(result).to be false
        expect(second_job.reload.queued?).to be true
      end

      it 'respects increased concurrency_limit immediately' do
        # Fill up both slots (limit is 2)
        2.times do |i|
          job = create(:job, client: client, status: :queued)
          described_class.acquire_and_start!(job, worker_id: "w#{i}")
        end

        # Third job is blocked
        third_job = create(:job, client: client, status: :queued)
        expect(described_class.acquire_and_start!(third_job, worker_id: 'w3')).to be false

        # Admin increases limit to 5
        client.update!(concurrency_limit: 5)

        # Now the third job can start
        expect(described_class.acquire_and_start!(third_job, worker_id: 'w3')).to be true
      end
    end

    context 'cross-client isolation' do
      it 'does not count jobs from other clients' do
        other_client = create(:client, concurrency_limit: 1)

        # Fill up other_client's slots
        other_job = create(:job, client: other_client, status: :queued)
        described_class.acquire_and_start!(other_job, worker_id: 'w1')

        # Our client's slots should still be free
        our_job = create(:job, client: client, status: :queued)
        result = described_class.acquire_and_start!(our_job, worker_id: 'w2')
        expect(result).to be true
      end
    end

    context 'job already started by another worker' do
      it 'returns false if job is no longer queued' do
        job = create(:job, client: client, status: :running, started_at: 1.minute.ago)
        result = described_class.acquire_and_start!(job, worker_id: 'w1')
        expect(result).to be false
      end
    end

    context 'race condition - concurrent slot acquisition', :concurrency do
      let(:client) { create(:client, concurrency_limit: 1) }

      it 'only one of two concurrent workers acquires the slot' do
        job1 = create(:job, client: client, status: :queued)
        job2 = create(:job, client: client, status: :queued)

        results = []
        threads = [job1, job2].map.with_index do |job, i|
          Thread.new do
            result = described_class.acquire_and_start!(job, worker_id: "worker_#{i}")
            results << result
          end
        end

        threads.each(&:join)

        expect(results.count(true)).to eq(1)
        expect(results.count(false)).to eq(1)
        expect(Job.where(client_id: client.id, status: :running).count).to eq(1)
      end
    end
  end
end
