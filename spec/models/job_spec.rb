require 'rails_helper'

RSpec.describe Job, type: :model do
  let(:client) { create(:client) }

  describe 'associations' do
    it { should belong_to(:client) }
  end

  describe 'validations' do
    it { should validate_presence_of(:workload) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:priority) }
  end

  describe 'enums' do
    it 'defines status values' do
      expect(Job.statuses).to eq({
        'queued' => 0, 'running' => 1, 'completed' => 2, 'failed' => 3, 'stalled' => 4
      })
    end

    it 'defines priority values' do
      expect(Job.priorities).to eq({
        'low' => 0, 'medium' => 1, 'high' => 2
      })
    end
  end

  describe 'defaults' do
    it 'starts in queued status' do
      job = create(:job, client: client)
      expect(job.queued?).to be true
    end

    it 'starts with 0 attempts' do
      job = create(:job, client: client)
      expect(job.attempts).to eq(0)
    end

    it 'defaults max_retries to 3' do
      job = create(:job, client: client)
      expect(job.max_retries).to eq(3)
    end
  end

  describe 'idempotency_key' do
    it 'allows nil idempotency_key' do
      job = create(:job, client: client)
      expect(job.idempotency_key).to be_nil
    end

    it 'enforces uniqueness when provided' do
      create(:job, client: client, idempotency_key: 'unique_123')
      duplicate = build(:job, client: client, idempotency_key: 'unique_123')
      expect(duplicate).not_to be_valid
    end
  end

  describe 'state machine' do
    describe 'initial state' do
      it 'starts as queued' do
        job = create(:job, client: client)
        expect(job.aasm.current_state).to eq(:queued)
      end
    end

    describe 'valid transitions' do
      describe 'queued -> running (start!)' do
        let(:job) { create(:job, client: client) }

        it 'transitions to running' do
          job.start!
          expect(job.reload.running?).to be true
        end

        it 'sets started_at timestamp' do
          freeze_time do
            job.start!
            expect(job.started_at).to eq(Time.current)
          end
        end

        it 'sets locked_at timestamp' do
          freeze_time do
            job.start!
            expect(job.locked_at).to eq(Time.current)
          end
        end

        it 'increments attempts' do
          expect { job.start! }.to change { job.attempts }.by(1)
        end

        it 'persists the transition to the database' do
          job.start!
          expect(Job.find(job.id).status).to eq('running')
        end
      end

      describe 'running -> completed (complete!)' do
        let(:job) { create(:job, client: client, status: :running, started_at: 1.minute.ago, locked_by: 'worker_1') }

        it 'transitions to completed' do
          job.complete!
          expect(job.reload.completed?).to be true
        end

        it 'sets completed_at timestamp' do
          freeze_time do
            job.complete!
            expect(job.completed_at).to eq(Time.current)
          end
        end

        it 'clears lock fields' do
          job.complete!
          expect(job.locked_by).to be_nil
          expect(job.locked_at).to be_nil
        end
      end

      describe 'running -> failed (mark_failed!)' do
        let(:job) { create(:job, client: client, status: :running, started_at: 1.minute.ago, locked_by: 'worker_1') }

        it 'transitions to failed' do
          job.mark_failed!
          expect(job.reload.failed?).to be true
        end

        it 'clears lock fields' do
          job.mark_failed!
          expect(job.locked_by).to be_nil
          expect(job.locked_at).to be_nil
        end
      end

      describe 'running -> stalled (stall!)' do
        let(:job) { create(:job, client: client, status: :running, started_at: 2.minutes.ago, locked_by: 'worker_1') }

        it 'transitions to stalled' do
          job.stall!
          expect(job.reload.stalled?).to be true
        end

        it 'clears lock fields' do
          job.stall!
          expect(job.locked_by).to be_nil
          expect(job.locked_at).to be_nil
        end
      end

      describe 'failed -> queued (re_enqueue!)' do
        let(:job) { create(:job, client: client, status: :failed, attempts: 1, started_at: 5.minutes.ago) }

        it 'transitions to queued' do
          job.re_enqueue!
          expect(job.reload.queued?).to be true
        end

        it 'resets timestamps' do
          job.re_enqueue!
          expect(job.started_at).to be_nil
          expect(job.completed_at).to be_nil
        end

        it 'clears lock fields' do
          job.re_enqueue!
          expect(job.locked_by).to be_nil
          expect(job.locked_at).to be_nil
        end
      end

      describe 'stalled -> queued (re_enqueue!)' do
        let(:job) { create(:job, client: client, status: :stalled, started_at: 5.minutes.ago) }

        it 'transitions to queued' do
          job.re_enqueue!
          expect(job.reload.queued?).to be true
        end
      end
    end

    #
    describe 'invalid transitions' do
      it 'rejects queued -> completed' do
        job = create(:job, client: client, status: :queued)
        expect { job.complete! }.to raise_error(AASM::InvalidTransition)
      end

      it 'rejects queued -> failed' do
        job = create(:job, client: client, status: :queued)
        expect { job.mark_failed! }.to raise_error(AASM::InvalidTransition)
      end

      it 'rejects queued -> stalled' do
        job = create(:job, client: client, status: :queued)
        expect { job.stall! }.to raise_error(AASM::InvalidTransition)
      end

      it 'rejects completed -> running' do
        job = create(:job, client: client, status: :completed)
        expect { job.start! }.to raise_error(AASM::InvalidTransition)
      end

      it 'rejects completed -> queued' do
        job = create(:job, client: client, status: :completed)
        expect { job.re_enqueue! }.to raise_error(AASM::InvalidTransition)
      end

      it 'rejects failed -> running (must re_enqueue first)' do
        job = create(:job, client: client, status: :failed)
        expect { job.start! }.to raise_error(AASM::InvalidTransition)
      end

      it 'rejects running -> queued' do
        job = create(:job, client: client, status: :running, started_at: 1.minute.ago)
        expect { job.re_enqueue! }.to raise_error(AASM::InvalidTransition)
      end

      it 'does not change state on invalid transition' do
        job = create(:job, client: client, status: :queued)
        begin
          job.complete!
        rescue AASM::InvalidTransition
          # expected
        end
        expect(job.reload.queued?).to be true
      end
    end

    #
    describe 'transition guards' do
      it 'queued job may_start?' do
        job = create(:job, client: client, status: :queued)
        expect(job.may_start?).to be true
        expect(job.may_complete?).to be false
        expect(job.may_mark_failed?).to be false
      end

      it 'running job may complete, fail, or stall' do
        job = create(:job, client: client, status: :running, started_at: 1.minute.ago)
        expect(job.may_start?).to be false
        expect(job.may_complete?).to be true
        expect(job.may_mark_failed?).to be true
        expect(job.may_stall?).to be true
      end

      it 'completed job has no valid transitions' do
        job = create(:job, client: client, status: :completed)
        expect(job.may_start?).to be false
        expect(job.may_complete?).to be false
        expect(job.may_mark_failed?).to be false
        expect(job.may_re_enqueue?).to be false
      end

      it 'failed job may only re_enqueue' do
        job = create(:job, client: client, status: :failed)
        expect(job.may_re_enqueue?).to be true
        expect(job.may_start?).to be false
      end
    end

    #
    describe 'atomic transitions', :concurrency do
      it 'only one worker can start a queued job when two attempt simultaneously' do
        job = create(:job, client: client, status: :queued)

        results = []
        threads = 2.times.map do
          Thread.new do
            begin
              j = Job.find(job.id)
              j.start!
              results << :started
            rescue AASM::InvalidTransition
              results << :rejected
            end
          end
        end

        threads.each(&:join)

        expect(results.count(:started)).to eq(1)
        expect(results.count(:rejected)).to eq(1)
        expect(job.reload.running?).to be true
      end

      it 'only one worker can complete a running job when two attempt simultaneously' do
        job = create(:job, client: client, status: :running, started_at: 1.minute.ago, locked_by: 'worker_1')

        results = []
        threads = 2.times.map do
          Thread.new do
            begin
              j = Job.find(job.id)
              j.complete!
              results << :completed
            rescue AASM::InvalidTransition
              results << :rejected
            end
          end
        end

        threads.each(&:join)

        expect(results.count(:completed)).to eq(1)
        expect(results.count(:rejected)).to eq(1)
        expect(job.reload.completed?).to be true
      end
    end

    #
    describe 'crash recovery' do
      it 'state remains queued if transition to running is interrupted (rollback)' do
        job = create(:job, client: client, status: :queued)

        begin
          Job.transaction do
            j = Job.lock.find(job.id)
            j.status = :running
            j.save!
            raise ActiveRecord::Rollback
          end
        rescue
          # simulating crash during transition
        end

        expect(job.reload.queued?).to be true
      end
    end
  end
end
