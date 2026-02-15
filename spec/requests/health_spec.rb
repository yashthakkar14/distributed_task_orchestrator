require 'rails_helper'

RSpec.describe 'Health endpoint', type: :request do
  describe 'GET /health/detailed' do
    let(:mock_queue) { instance_double(Sidekiq::Queue, latency: 0.5) }

    before do
      allow(Sidekiq::Queue).to receive(:new).with('default').and_return(mock_queue)
    end

    it 'returns 200 when healthy' do
      get '/health/detailed'
      expect(response).to have_http_status(:ok)
    end

    it 'returns JSON with expected structure' do
      get '/health/detailed'
      body = JSON.parse(response.body)

      expect(body['status']).to eq('ok')
      expect(body['timestamp']).to be_present
      expect(body['database']).to include('connected' => true)
      expect(body['redis']).to include('connected' => true)
      expect(body['sidekiq']).to include('default_queue_latency')
      expect(body['queues']).to include('queued', 'running', 'failed', 'stalled', 'completed')
      expect(body['clients']).to be_an(Array)
    end

    it 'reports queue counts accurately' do
      client = create(:client)
      create_list(:job, 3, client: client, status: :queued)
      create(:job, client: client, status: :running, started_at: 1.minute.ago)
      create(:job, client: client, status: :failed)

      get '/health/detailed'
      queues = JSON.parse(response.body)['queues']

      expect(queues['queued']).to eq(3)
      expect(queues['running']).to eq(1)
      expect(queues['failed']).to eq(1)
    end

    it 'reports per-client stats' do
      client = create(:client, concurrency_limit: 5)
      create(:job, client: client, status: :running, started_at: 1.minute.ago)
      create(:job, client: client, status: :queued)

      get '/health/detailed'
      clients = JSON.parse(response.body)['clients']
      client_stat = clients.find { |c| c['id'] == client.id }

      expect(client_stat['name']).to eq(client.name)
      expect(client_stat['concurrency_limit']).to eq(5)
      expect(client_stat['running_jobs']).to eq(1)
      expect(client_stat['queued_jobs']).to eq(1)
      expect(client_stat['available_slots']).to eq(4)
    end

    context 'when database is down' do
      it 'returns 503 with degraded status' do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)

        get '/health/detailed'

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['status']).to eq('degraded')
        expect(body['database']['connected']).to be false
      end
    end

    context 'when Redis is down' do
      it 'returns 503 with degraded status' do
        allow(REDIS).to receive(:ping).and_raise(Redis::CannotConnectError)

        get '/health/detailed'

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['status']).to eq('degraded')
        expect(body['redis']['connected']).to be false
      end
    end

    context 'when Sidekiq latency exceeds threshold' do
      let(:mock_queue) { instance_double(Sidekiq::Queue, latency: 20.0) }

      it 'returns 503 with degraded status' do
        get '/health/detailed'

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['status']).to eq('degraded')
        expect(body['sidekiq']['latency_exceeded']).to be true
        expect(body['sidekiq']['default_queue_latency']).to eq(20.0)
      end
    end

    context 'when Sidekiq latency is within threshold' do
      let(:mock_queue) { instance_double(Sidekiq::Queue, latency: 3.0) }

      it 'returns 200 with ok status' do
        get '/health/detailed'

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['sidekiq']['latency_exceeded']).to be false
        expect(body['sidekiq']['default_queue_latency']).to eq(3.0)
      end
    end
  end
end
