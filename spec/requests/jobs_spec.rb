require 'rails_helper'

RSpec.describe 'POST /jobs', type: :request do
  let!(:client) { create(:client, name: 'client_alpha', concurrency_limit: 3) }

  let(:valid_params) do
    {
      client_id: 'client_alpha',
      priority: 'high',
      workload: 'simulated_task_42'
    }
  end

  describe 'successful submission' do
    it 'returns 201 with job details' do
      post '/jobs', params: valid_params, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['id']).to be_present
      expect(body['status']).to eq('queued')
      expect(body['client_id']).to eq('client_alpha')
      expect(body['priority']).to eq('high')
      expect(body['workload']).to eq('simulated_task_42')
    end

    it 'persists the job in queued state' do
      expect { post '/jobs', params: valid_params, as: :json }.to change(Job, :count).by(1)

      job = Job.last
      expect(job.queued?).to be true
      expect(job.client).to eq(client)
    end

    it 'enqueues a JobExecutionWorker' do
      expect(JobExecutionWorker).to receive(:perform_async).with(an_instance_of(Integer))
      post '/jobs', params: valid_params, as: :json
    end
  end

  describe 'client not found' do
    it 'returns 404' do
      post '/jobs', params: valid_params.merge(client_id: 'nonexistent'), as: :json

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body['error']).to include('not found')
    end

    it 'does not create a job' do
      expect { post '/jobs', params: valid_params.merge(client_id: 'nonexistent'), as: :json }
        .not_to change(Job, :count)
    end
  end

  describe 'missing required fields' do
    it 'returns 422 when workload is missing' do
      post '/jobs', params: valid_params.except(:workload), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 when priority is invalid' do
      post '/jobs', params: valid_params.merge(priority: 'urgent'), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'idempotency' do
    it 'rejects duplicate idempotency_key' do
      post '/jobs', params: valid_params.merge(idempotency_key: 'unique_123'), as: :json
      expect(response).to have_http_status(:created)

      post '/jobs', params: valid_params.merge(idempotency_key: 'unique_123'), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'allows submissions without idempotency_key' do
      2.times { post '/jobs', params: valid_params, as: :json }
      expect(Job.count).to eq(2)
    end
  end
end
