Sidekiq.configure_server do |config|
  config.on(:startup) do
    # Clear any previously scheduled instances to prevent duplicates on restart
    scheduled = Sidekiq::ScheduledSet.new
    scheduled.select { |job| %w[SchedulerWorker HeartbeatMonitorWorker].include?(job.klass) }.each(&:delete)

    # Start the periodic scheduler when Sidekiq process boots
    SchedulerWorker.perform_async

    # Start the heartbeat monitor
    HeartbeatMonitorWorker.perform_async
  end
end
