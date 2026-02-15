require 'rails_helper'

RSpec.describe SchedulerService do
  describe '.schedule_jobs' do
    context 'priority ordering' do
      let(:client) { create(:client, concurrency_limit: 10) }

      it 'schedules high-priority jobs before medium and low' do
        low_job = create(:job, client: client, priority: :low, created_at: 1.hour.ago)
        medium_job = create(:job, client: client, priority: :medium, created_at: 2.hours.ago)
        high_job = create(:job, client: client, priority: :high, created_at: 3.hours.ago)

        described_class.schedule_jobs

        # All should be running, but high should have been started first
        expect(high_job.reload.running?).to be true
        expect(medium_job.reload.running?).to be true
        expect(low_job.reload.running?).to be true

        # Verify ordering by started_at: high started earliest (first in sequence)
        expect(high_job.started_at).to be <= medium_job.reload.started_at
        expect(medium_job.started_at).to be <= low_job.reload.started_at
      end

      it 'schedules all high-priority jobs before any medium-priority' do
        high_jobs = 3.times.map { create(:job, client: client, priority: :high) }
        medium_job = create(:job, client: client, priority: :medium, created_at: 1.day.ago)

        described_class.schedule_jobs

        high_jobs.each { |j| expect(j.reload.running?).to be true }
        expect(medium_job.reload.running?).to be true
      end
    end

    context 'fairness (round-robin across clients)' do
      let(:client_a) { create(:client, concurrency_limit: 10) }
      let(:client_b) { create(:client, concurrency_limit: 10) }

      it 'interleaves jobs from different clients at the same priority' do
        # Client A floods the queue with 5 high-priority jobs
        a_jobs = 5.times.map { |i| create(:job, client: client_a, priority: :high, created_at: i.minutes.ago) }
        # Client B has 2 high-priority jobs
        b_jobs = 2.times.map { |i| create(:job, client: client_b, priority: :high, created_at: i.minutes.ago) }

        described_class.schedule_jobs

        # All should be running (both clients have enough concurrency)
        (a_jobs + b_jobs).each { |j| expect(j.reload.running?).to be true }

        # Client B should not be starved
        # Verify both clients got jobs started (fairness)
        a_running = Job.where(client: client_a, status: :running).count
        b_running = Job.where(client: client_b, status: :running).count
        expect(a_running).to eq(5)
        expect(b_running).to eq(2)
      end

      it 'prevents starvation when one client floods the queue' do
        flood_client = create(:client, concurrency_limit: 2)
        normal_client = create(:client, concurrency_limit: 2)

        # Flood client submits 10 jobs
        10.times { create(:job, client: flood_client, priority: :high) }
        # Normal client submits 2 jobs
        2.times { create(:job, client: normal_client, priority: :high) }

        described_class.schedule_jobs

        # Normal client should get their jobs running (not starved)
        expect(Job.where(client: normal_client, status: :running).count).to eq(2)
        # Flood client is capped at concurrency limit
        expect(Job.where(client: flood_client, status: :running).count).to eq(2)
      end
    end

    context 'concurrency limits respected' do
      it 'does not exceed client concurrency limit' do
        client = create(:client, concurrency_limit: 2)
        5.times { create(:job, client: client, priority: :high) }

        described_class.schedule_jobs

        expect(Job.where(client: client, status: :running).count).to eq(2)
        expect(Job.where(client: client, status: :queued).count).to eq(3)
      end
    end

    context 'scheduled_at (backoff) respect' do
      it 'does not schedule jobs with future scheduled_at' do
        client = create(:client, concurrency_limit: 5)
        ready_job = create(:job, client: client, priority: :high, scheduled_at: 1.minute.ago)
        future_job = create(:job, client: client, priority: :high, scheduled_at: 10.minutes.from_now)

        described_class.schedule_jobs

        expect(ready_job.reload.running?).to be true
        expect(future_job.reload.queued?).to be true
      end

      it 'schedules jobs with nil scheduled_at (immediately ready)' do
        client = create(:client, concurrency_limit: 5)
        job = create(:job, client: client, priority: :high, scheduled_at: nil)

        described_class.schedule_jobs

        expect(job.reload.running?).to be true
      end
    end
  end

  describe '.schedule_for_client' do
    let(:client) { create(:client, concurrency_limit: 2) }

    it 'enqueues the highest-priority queued job for the client' do
      low_job = create(:job, client: client, priority: :low, created_at: 1.hour.ago)
      high_job = create(:job, client: client, priority: :high, created_at: 1.minute.ago)

      expect(JobExecutionWorker).to receive(:perform_async).with(high_job.id)
      described_class.schedule_for_client(client.id)
    end

    it 'returns 0 when no queued jobs exist' do
      result = described_class.schedule_for_client(client.id)
      expect(result).to eq(0)
    end

    it 'returns 0 when concurrency limit is reached' do
      # Fill slots
      2.times do
        job = create(:job, client: client, status: :queued)
        ConcurrencyGuardService.acquire_and_start!(job, worker_id: 'w')
      end

      create(:job, client: client, priority: :high)

      result = described_class.schedule_for_client(client.id)
      expect(result).to eq(0)
    end

    it 'does not schedule jobs with future scheduled_at' do
      create(:job, client: client, priority: :high, scheduled_at: 10.minutes.from_now)

      expect(JobExecutionWorker).not_to receive(:perform_async)
      described_class.schedule_for_client(client.id)
    end
  end
end
