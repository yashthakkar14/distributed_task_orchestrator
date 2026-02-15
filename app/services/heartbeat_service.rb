class HeartbeatService
  KEY_PREFIX = "heartbeat:job"
  TTL = 60       # key expires if not refreshed
  INTERVAL = 20  # pulse frequency

  def self.pulse(job_id)
    REDIS.set("#{KEY_PREFIX}:#{job_id}", Time.current.to_i, ex: TTL)
  end

  def self.alive?(job_id)
    REDIS.exists?("#{KEY_PREFIX}:#{job_id}")
  end

  def self.clear(job_id)
    REDIS.del("#{KEY_PREFIX}:#{job_id}")
  end
end
