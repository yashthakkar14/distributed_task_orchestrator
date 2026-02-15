class RetryService
  MAX_BACKOFF = 300 # 5 minutes

  def self.attempt_retry(job)
    return false unless job.failed? || job.stalled?
    return false if job.attempts >= job.max_retries

    backoff = calculate_backoff(job.attempts)
    job.update_column(:scheduled_at, Time.current + backoff)
    job.re_enqueue!
    true
  rescue AASM::InvalidTransition
    false
  end

  # 2^attempts seconds, capped at MAX_BACKOFF
  def self.calculate_backoff(attempts)
    [2**attempts, MAX_BACKOFF].min.seconds
  end
end
