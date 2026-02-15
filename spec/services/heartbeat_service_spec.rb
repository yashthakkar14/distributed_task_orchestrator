require 'rails_helper'

RSpec.describe HeartbeatService do
  let(:job_id) { 42 }

  after { REDIS.del("heartbeat:job:#{job_id}") }

  describe '.pulse' do
    it 'sets a Redis key with the job ID' do
      described_class.pulse(job_id)
      expect(REDIS.get("heartbeat:job:#{job_id}")).to be_present
    end

    it 'sets a TTL of 60 seconds' do
      described_class.pulse(job_id)
      ttl = REDIS.ttl("heartbeat:job:#{job_id}")
      expect(ttl).to be_between(55, 60)
    end
  end

  describe '.alive?' do
    it 'returns true when heartbeat exists' do
      described_class.pulse(job_id)
      expect(described_class.alive?(job_id)).to be true
    end

    it 'returns false when no heartbeat' do
      expect(described_class.alive?(job_id)).to be false
    end
  end

  describe '.clear' do
    it 'removes the heartbeat key' do
      described_class.pulse(job_id)
      described_class.clear(job_id)
      expect(described_class.alive?(job_id)).to be false
    end
  end
end
