class CreateJobs < ActiveRecord::Migration[7.0]
  def change
    create_table :jobs do |t|
      t.references :client, null: false, foreign_key: true

      # State machine (queued=0, running=1, completed=2, failed=3, stalled=4)
      t.integer :status, null: false, default: 0

      # Priority (low=0, medium=1, high=2)
      t.integer :priority, null: false, default: 0

      # The simulated task to execute
      t.string :workload, null: false

      # Retry tracking
      t.integer :attempts, null: false, default: 0
      t.integer :max_retries, null: false, default: 3
      t.text :last_error
      t.datetime :scheduled_at

      # Execution timestamps
      t.datetime :started_at
      t.datetime :completed_at

      # Which worker holds this job
      t.string :locked_by
      t.datetime :locked_at

      # Prevent duplicate submissions
      t.string :idempotency_key

      t.timestamps
    end

    # Scheduler query: find queued jobs ordered by priority (high first), then age (oldest first)
    add_index :jobs, [:status, :priority, :created_at], name: 'idx_jobs_scheduling'

    # Concurrency guard: count running jobs per client
    add_index :jobs, [:client_id, :status], name: 'idx_jobs_client_status'

    # Retry scheduling: find jobs ready to retry
    add_index :jobs, [:status, :scheduled_at], name: 'idx_jobs_retry_scheduling'

    # Unique when provided, NULLs allowed
    add_index :jobs, :idempotency_key, unique: true
  end
end
