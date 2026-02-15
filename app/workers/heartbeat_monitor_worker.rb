class HeartbeatMonitorWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'critical', retry: false

  INTERVAL = 30

  def perform
    stall_dead_jobs
  ensure
    self.class.perform_in(INTERVAL)
  end

  private

  def stall_dead_jobs
    Job.where(status: :running).find_each do |job|
      next if HeartbeatService.alive?(job.id)

      # Grace period: skip jobs that just started (heartbeat might not have pulsed yet)
      next if job.started_at && job.started_at > 60.seconds.ago

      begin
        job.stall!
        Rails.logger.warn("[HeartbeatMonitor] Stalled job #{job.id}")
        RetryService.attempt_retry(job)
        SchedulerService.schedule_for_client(job.client_id)
      rescue AASM::InvalidTransition
        # Already stalled by another monitor instance
      end
    end
  end
end
