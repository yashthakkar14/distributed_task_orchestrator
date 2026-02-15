class Job < ApplicationRecord
  include AASM

  belongs_to :client

  enum status: {
    queued: 0,
    running: 1,
    completed: 2,
    failed: 3,
    stalled: 4
  }

  enum priority: {
    low: 0,
    medium: 1,
    high: 2
  }

  validates :workload, presence: true
  validates :status, presence: true
  validates :priority, presence: true
  validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :idempotency_key, uniqueness: true, allow_nil: true

  aasm column: :status, enum: true, whiny_transitions: true, requires_lock: true do
    state :queued, initial: true
    state :running
    state :completed
    state :failed
    state :stalled

    event :start do
      before do
        self.started_at = Time.current
        self.locked_at = Time.current
        self.attempts += 1
      end

      transitions from: :queued, to: :running
    end

    event :complete do
      before do
        self.completed_at = Time.current
        self.locked_by = nil
        self.locked_at = nil
      end

      transitions from: :running, to: :completed
    end

    # mark_failed instead of fail to avoid conflict with Kernel#fail
    event :mark_failed do
      before do
        self.locked_by = nil
        self.locked_at = nil
      end

      transitions from: :running, to: :failed
    end

    event :stall do
      before do
        self.locked_by = nil
        self.locked_at = nil
      end

      transitions from: :running, to: :stalled
    end

    event :re_enqueue do
      before do
        self.started_at = nil
        self.completed_at = nil
        self.locked_by = nil
        self.locked_at = nil
      end

      transitions from: [:failed, :stalled], to: :queued
    end
  end
end
