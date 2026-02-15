require 'rails_helper'

RSpec.describe JobSubmissionService do
  let!(:client) { create(:client, name: 'test_client', concurrency_limit: 3) }

  describe '#call' do
    context 'with valid params' do
      let(:params) { { client_id: 'test_client', priority: 'medium', workload: 'task_1' } }

      it 'returns a successful result' do
        result = described_class.new(params).call
        expect(result.success?).to be true
        expect(result.job).to be_persisted
        expect(result.job.queued?).to be true
      end

      it 'enqueues a worker' do
        expect(JobExecutionWorker).to receive(:perform_async)
        described_class.new(params).call
      end
    end

    context 'with unknown client' do
      let(:params) { { client_id: 'unknown', priority: 'low', workload: 'task_1' } }

      it 'returns failure with not_found status' do
        result = described_class.new(params).call
        expect(result.success?).to be false
        expect(result.status).to eq(:not_found)
      end
    end

    context 'with missing workload' do
      let(:params) { { client_id: 'test_client', priority: 'low', workload: '' } }

      it 'returns failure with validation errors' do
        result = described_class.new(params).call
        expect(result.success?).to be false
        expect(result.status).to eq(:unprocessable_entity)
      end
    end

    context 'queue depth limit exceeded' do
      let(:params) { { client_id: 'test_client', priority: 'medium', workload: 'task_1' } }

      before do
        stub_const("JobSubmissionService::QUEUE_DEPTH_LIMIT", 5)
        5.times { create(:job, client: client, status: :queued, workload: 'existing') }
      end

      it 'rejects submission with too_many_requests status' do
        result = described_class.new(params).call
        expect(result.success?).to be false
        expect(result.status).to eq(:too_many_requests)
        expect(result.error).to include('Queue depth limit exceeded')
      end

      it 'allows submission when some jobs have completed' do
        client.jobs.where(status: :queued).first.update!(status: :completed, completed_at: Time.current)
        result = described_class.new(params).call
        expect(result.success?).to be true
      end
    end
  end
end
