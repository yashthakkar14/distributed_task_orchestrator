class SchedulerWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'critical', retry: false

  INTERVAL = 5

  def perform
    SchedulerService.schedule_jobs
  ensure
    self.class.perform_in(INTERVAL)
  end
end
