class JobExecutionWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: false

  def perform(job_id)
    job = Job.find_by(id: job_id)
    return unless job

    if job.queued?
      return unless job.may_start?
      acquired = ConcurrencyGuardService.acquire_and_start!(job, worker_id: worker_identity)
      return unless acquired
    elsif job.running?
      # Transfer lock from scheduler to this worker (prevents duplicate execution)
      transferred = Job.where(id: job.id)
                       .where("locked_by LIKE 'scheduler:%'")
                       .update_all(locked_by: worker_identity)
      return unless transferred > 0
    else
      return
    end

    heartbeat_thread = start_heartbeat(job)

    begin
      execute_workload(job)
      job.complete!
    rescue StandardError => e
      handle_failure(job, e)
    ensure
      stop_heartbeat(heartbeat_thread, job)
    end

    SchedulerService.schedule_for_client(job.client_id)
  end

  private

  def worker_identity
    @worker_identity ||= "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}"
  end

  def start_heartbeat(job)
    HeartbeatService.pulse(job.id)

    Thread.new do
      loop do
        sleep(HeartbeatService::INTERVAL)
        HeartbeatService.pulse(job.id)
      end
    rescue StandardError => e
      Rails.logger.error("[Heartbeat] Thread error for job #{job.id}: #{e.message}")
    end
  end

  def stop_heartbeat(thread, job)
    thread&.kill
    HeartbeatService.clear(job.id)
  end

  def execute_workload(job)
    duration = case job.workload
               when /fast/  then 1
               when /slow/  then 5
               when /error/ then raise StandardError, "Simulated task failure for #{job.workload}"
               else rand(2..4)
               end
    sleep(duration)
  end

  def handle_failure(job, error)
    return unless job.may_mark_failed?

    job.update_column(:last_error, error.message)
    job.mark_failed!
    RetryService.attempt_retry(job)
  rescue StandardError => e
    Rails.logger.error("[JobExecutionWorker] Failed to mark job #{job.id} as failed: #{e.message}")
  end
end
