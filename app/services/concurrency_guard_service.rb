class ConcurrencyGuardService
  # Lock client row, check slot availability, start job. All in one transaction.
  def self.acquire_and_start!(job, worker_id:)
    ActiveRecord::Base.transaction do
      client = Client.lock("FOR UPDATE").find(job.client_id)
      running_count = Job.where(client_id: client.id, status: :running).count
      return false if running_count >= client.concurrency_limit

      job.start!
      job.update_column(:locked_by, worker_id)
      true
    end
  rescue AASM::InvalidTransition
    false
  end
end
