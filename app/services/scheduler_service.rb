class SchedulerService
  # Priority bands (high, medium, low), round-robin across clients within each band.
  def self.schedule_jobs
    total = 0
    [:high, :medium, :low].each do |priority|
      total += schedule_priority_band(priority)
    end
    total
  end

  # Schedule next job for a specific client (called when a slot frees up).
  def self.schedule_for_client(client_id)
    client = Client.find_by(id: client_id)
    return 0 unless client

    running_count = Job.where(client_id: client_id, status: :running).count
    return 0 if running_count >= client.concurrency_limit

    job = Job.where(client_id: client_id, status: :queued)
             .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
             .order(priority: :desc, created_at: :asc)
             .first
    return 0 unless job

    JobExecutionWorker.perform_async(job.id)
    1
  end

  class << self
    private

    def schedule_priority_band(priority)
      scheduled = 0

      loop do
        client_ids = ready_jobs_scope(priority).distinct.pluck(:client_id)
        break if client_ids.empty?

        round_scheduled = 0

        # One job per client per round (fair scheduling)
        client_ids.each do |client_id|
          client = Client.find(client_id)
          running_count = Job.where(client_id: client_id, status: :running).count
          next if running_count >= client.concurrency_limit

          job = ready_jobs_scope(priority)
                  .where(client_id: client_id)
                  .order(created_at: :asc)
                  .first
          next unless job

          worker_id = "scheduler:#{Socket.gethostname}:#{Process.pid}"
          if ConcurrencyGuardService.acquire_and_start!(job, worker_id: worker_id)
            JobExecutionWorker.perform_async(job.id)
            round_scheduled += 1
            scheduled += 1
          end
        end

        break if round_scheduled == 0
      end

      scheduled
    end

    def ready_jobs_scope(priority)
      Job.where(status: :queued, priority: priority)
         .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
    end
  end
end
