require 'rails_helper'

RSpec.describe RetryService do
  let(:client) { create(:client) }

  describe '.attempt_retry' do
    context 'failed job with retries remaining' do
      it 're-enqueues the job' do
        job = create(:job, client: client, status: :failed, attempts: 1, max_retries: 3)
        result = described_class.attempt_retry(job)
        expect(result).to be true
        expect(job.reload.queued?).to be true
      end

      it 'sets scheduled_at with backoff' do
        job = create(:job, client: client, status: :failed, attempts: 2, max_retries: 3)
        described_class.attempt_retry(job)
        expect(job.reload.scheduled_at).to be > Time.current
      end
    end

    context 'stalled job with retries remaining' do
      it 're-enqueues the job' do
        job = create(:job, client: client, status: :stalled, attempts: 1, max_retries: 3)
        result = described_class.attempt_retry(job)
        expect(result).to be true
        expect(job.reload.queued?).to be true
      end
    end

    context 'exhausted retries' do
      it 'returns false and does not change state' do
        job = create(:job, client: client, status: :failed, attempts: 3, max_retries: 3)
        result = described_class.attempt_retry(job)
        expect(result).to be false
        expect(job.reload.failed?).to be true
      end
    end

    context 'job not in retryable state' do
      it 'returns false for completed jobs' do
        job = create(:job, client: client, status: :completed, completed_at: Time.current)
        result = described_class.attempt_retry(job)
        expect(result).to be false
      end

      it 'returns false for queued jobs' do
        job = create(:job, client: client, status: :queued)
        result = described_class.attempt_retry(job)
        expect(result).to be false
      end
    end
  end

  describe '.calculate_backoff' do
    it 'returns exponential backoff' do
      expect(described_class.calculate_backoff(1)).to eq(2.seconds)
      expect(described_class.calculate_backoff(2)).to eq(4.seconds)
      expect(described_class.calculate_backoff(3)).to eq(8.seconds)
    end

    it 'caps at MAX_BACKOFF' do
      expect(described_class.calculate_backoff(20)).to eq(300.seconds)
    end
  end
end
