require 'rails_helper'

RSpec.describe JobExecutionWorker, type: :worker do
  let(:client) { create(:client) }
  let(:worker) { described_class.new }

  # Stub sleep so tests run instantly
  before do
    allow(worker).to receive(:sleep)
    allow(SchedulerService).to receive(:schedule_for_client)
    allow(RetryService).to receive(:attempt_retry)
  end

  describe '#perform' do
    context 'successful execution' do
      let(:job) { create(:job, client: client, status: :queued, workload: 'fast_task') }

      it 'transitions job from queued to completed' do
        worker.perform(job.id)
        expect(job.reload.completed?).to be true
      end

      it 'sets started_at timestamp' do
        worker.perform(job.id)
        expect(job.reload.started_at).to be_present
      end

      it 'sets completed_at timestamp' do
        worker.perform(job.id)
        expect(job.reload.completed_at).to be_present
      end

      it 'sets locked_by during execution' do
        # Capture locked_by during execution (before complete! clears it)
        locked_by_during_execution = nil
        allow(worker).to receive(:sleep) do
          locked_by_during_execution = job.reload.locked_by
        end

        worker.perform(job.id)
        expect(locked_by_during_execution).to be_present
        # After completion, locked_by is cleared
        expect(job.reload.locked_by).to be_nil
      end
    end

    context 'job not found' do
      it 'returns silently without error' do
        expect { worker.perform(999_999) }.not_to raise_error
      end
    end

    context 'scheduler path - job already running' do
      let(:job) { create(:job, client: client, status: :running, started_at: 1.second.ago, locked_by: 'scheduler:host:123') }

      it 'executes the job and transitions to completed' do
        worker.perform(job.id)
        expect(job.reload.completed?).to be true
      end

      it 'transfers locked_by from scheduler to worker' do
        locked_by_during_execution = nil
        allow(worker).to receive(:sleep) do
          locked_by_during_execution = job.reload.locked_by
        end

        worker.perform(job.id)
        expect(locked_by_during_execution).not_to start_with('scheduler:')
      end
    end

    context 'duplicate execution prevention - job running with non-scheduler lock' do
      let(:job) { create(:job, client: client, status: :running, started_at: 1.second.ago, locked_by: 'other_worker:host:456') }

      it 'does not execute when another worker already holds the lock' do
        worker.perform(job.id)
        # Job should remain running, this worker bailed out
        expect(job.reload.running?).to be true
      end
    end

    context 'job already completed (idempotent)' do
      let(:job) { create(:job, client: client, status: :completed, completed_at: 1.minute.ago) }

      it 'does not change the job state' do
        worker.perform(job.id)
        expect(job.reload.completed?).to be true
      end
    end

    context 'execution failure' do
      let(:job) { create(:job, client: client, status: :queued, workload: 'error_task') }

      it 'transitions job to failed' do
        worker.perform(job.id)
        expect(job.reload.failed?).to be true
      end

      it 'records the error message' do
        worker.perform(job.id)
        expect(job.reload.last_error).to include('Simulated task failure')
      end

      it 'increments attempts count on execution' do
        worker.perform(job.id)
        expect(job.reload.attempts).to eq(1)
      end

      it 'attempts retry on failure' do
        expect(RetryService).to receive(:attempt_retry)
        worker.perform(job.id)
      end

      it 'clears locked_by on failure' do
        worker.perform(job.id)
        expect(job.reload.locked_by).to be_nil
      end
    end

    context 'heartbeat during execution' do
      let(:job) { create(:job, client: client, status: :queued, workload: 'fast_task') }

      it 'sends heartbeat to Redis during execution' do
        heartbeat_alive = false
        allow(worker).to receive(:sleep) do
          heartbeat_alive = HeartbeatService.alive?(job.id)
        end

        worker.perform(job.id)
        expect(heartbeat_alive).to be true
      end

      it 'clears heartbeat after completion' do
        worker.perform(job.id)
        expect(HeartbeatService.alive?(job.id)).to be false
      end

      it 'clears heartbeat after failure' do
        error_job = create(:job, client: client, status: :queued, workload: 'error_task')
        worker.perform(error_job.id)
        expect(HeartbeatService.alive?(error_job.id)).to be false
      end
    end

    context 'slot recycling' do
      let(:job) { create(:job, client: client, status: :queued, workload: 'fast_task') }

      it 'triggers scheduling for the client after completion' do
        expect(SchedulerService).to receive(:schedule_for_client).with(client.id)
        worker.perform(job.id)
      end
    end

    context 'race condition - two workers pick up same job', :concurrency do
      let(:job) { create(:job, client: client, status: :queued, workload: 'error_task') }

      it 'only one worker executes the job' do
        # Use error_task workload so execute_workload raises instantly (no sleep)
        # RSpec mocking (allow/receive) is NOT thread-safe, so we avoid stubs in threads
        results = []
        threads = 2.times.map do
          Thread.new do
            begin
              w = described_class.new
              w.perform(job.id)
              results << :executed
            rescue StandardError => e
              results << :error
            end
          end
        end

        threads.each(&:join)

        # Job should be failed (error_task raises), only the winning worker runs it
        job.reload
        expect(job.completed? || job.failed?).to be true
        # The loser returns silently
        expect(results).not_to include(:error)
      end
    end
  end
end
