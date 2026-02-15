class HealthController < ApplicationController
  LATENCY_THRESHOLD = 15 # seconds

  def detailed
    db = database_health
    redis = redis_health
    sidekiq = sidekiq_health

    health = {
      status: 'ok',
      timestamp: Time.current.iso8601,
      database: db,
      redis: redis,
      sidekiq: sidekiq,
      queues: db[:connected] ? queue_stats : {},
      clients: db[:connected] ? client_stats : []
    }

    if !db[:connected] || !redis[:connected] || sidekiq[:latency_exceeded]
      health[:status] = 'degraded'
    end

    render json: health, status: health[:status] == 'ok' ? :ok : :service_unavailable
  end

  private

  def database_health
    ActiveRecord::Base.connection.execute('SELECT 1')
    { connected: true }
  rescue StandardError => e
    { connected: false, error: e.message }
  end

  def redis_health
    REDIS.ping
    { connected: true }
  rescue StandardError => e
    { connected: false, error: e.message }
  end

  def sidekiq_health
    queue = Sidekiq::Queue.new('default')
    latency = queue.latency
    {
      default_queue_latency: latency.round(2),
      latency_exceeded: latency > LATENCY_THRESHOLD
    }
  rescue StandardError => e
    { default_queue_latency: nil, latency_exceeded: false, error: e.message }
  end

  def queue_stats
    {
      queued: Job.where(status: :queued).count,
      running: Job.where(status: :running).count,
      failed: Job.where(status: :failed).count,
      stalled: Job.where(status: :stalled).count,
      completed: Job.where(status: :completed).count
    }
  end

  def client_stats
    Client.includes(:jobs).map do |client|
      {
        id: client.id,
        name: client.name,
        concurrency_limit: client.concurrency_limit,
        running_jobs: client.jobs.where(status: :running).count,
        queued_jobs: client.jobs.where(status: :queued).count,
        available_slots: [client.concurrency_limit - client.jobs.where(status: :running).count, 0].max
      }
    end
  end
end
