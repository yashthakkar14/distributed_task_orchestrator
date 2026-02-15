class JobSubmissionService
  Result = Struct.new(:success?, :job, :error, :status, keyword_init: true)

  QUEUE_DEPTH_LIMIT = 10_000

  def initialize(params)
    @client_id = params[:client_id]
    @priority = params[:priority]
    @workload = params[:workload]
    @idempotency_key = params[:idempotency_key]
  end

  def call
    client = Client.find_by(name: @client_id)
    return Result.new(success?: false, error: "Client '#{@client_id}' not found", status: :not_found) unless client

    queued_count = client.jobs.where(status: :queued).count
    if queued_count >= QUEUE_DEPTH_LIMIT
      return Result.new(success?: false, error: "Queue depth limit exceeded (#{QUEUE_DEPTH_LIMIT} queued jobs). Please wait for existing jobs to complete.", status: :too_many_requests)
    end

    job = client.jobs.new(
      priority: @priority,
      workload: @workload,
      idempotency_key: @idempotency_key.presence
    )

    if job.save
      JobExecutionWorker.perform_async(job.id)
      Result.new(success?: true, job: job)
    else
      Result.new(success?: false, error: job.errors.full_messages.join(', '), status: :unprocessable_entity)
    end
  rescue ArgumentError => e
    Result.new(success?: false, error: e.message, status: :unprocessable_entity)
  end
end
