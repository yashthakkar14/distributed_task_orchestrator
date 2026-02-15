require 'rails_helper'

RSpec.describe HeartbeatMonitorWorker, type: :worker do
  let(:client) { create(:client) }
  let(:monitor) { described_class.new }

  # Stub self-rescheduling and retry to isolate monitor behavior
  before do
    allow(described_class).to receive(:perform_in)
    allow(RetryService).to receive(:attempt_retry)
  end

  describe '#perform' do
    context 'job with active heartbeat' do
      it 'does not stall the job' do
        job = create(:job, client: client, status: :running, started_at: 2.minutes.ago)
        HeartbeatService.pulse(job.id)

        monitor.perform

        expect(job.reload.running?).to be true
      end
    end

    context 'job with expired heartbeat (no Redis key)' do
      it 'transitions job to stalled' do
        job = create(:job, client: client, status: :running, started_at: 2.minutes.ago, locked_by: 'dead_worker')

        monitor.perform

        expect(job.reload.stalled?).to be true
      end

      it 'clears lock fields' do
        job = create(:job, client: client, status: :running, started_at: 2.minutes.ago, locked_by: 'dead_worker')

        monitor.perform

        job.reload
        expect(job.locked_by).to be_nil
        expect(job.locked_at).to be_nil
      end

      it 'triggers scheduling for the client (slot freed)' do
        job = create(:job, client: client, status: :running, started_at: 2.minutes.ago, locked_by: 'dead_worker')

        expect(SchedulerService).to receive(:schedule_for_client).with(client.id)
        monitor.perform
      end

      it 'attempts retry for stalled jobs' do
        job = create(:job, client: client, status: :running, started_at: 2.minutes.ago, locked_by: 'dead_worker')
        expect(RetryService).to receive(:attempt_retry)
        monitor.perform
      end
    end

    context 'grace period for recently started jobs' do
      it 'does not stall jobs started less than 60 seconds ago' do
        job = create(:job, client: client, status: :running, started_at: 30.seconds.ago, locked_by: 'new_worker')
        # No heartbeat in Redis yet (worker hasn't started executing)

        monitor.perform

        expect(job.reload.running?).to be true
      end
    end

    context 'multiple running jobs' do
      it 'only stalls jobs without heartbeats' do
        healthy_job = create(:job, client: client, status: :running, started_at: 2.minutes.ago)
        HeartbeatService.pulse(healthy_job.id)

        dead_job = create(:job, client: client, status: :running, started_at: 2.minutes.ago, locked_by: 'dead')

        monitor.perform

        expect(healthy_job.reload.running?).to be true
        expect(dead_job.reload.stalled?).to be true
      end
    end

    context 'self-rescheduling' do
      it 'reschedules itself after execution' do
        expect(described_class).to receive(:perform_in).with(described_class::INTERVAL)
        monitor.perform
      end
    end
  end
end
