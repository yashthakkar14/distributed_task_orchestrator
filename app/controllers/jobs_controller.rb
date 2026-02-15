class JobsController < ApplicationController
  def create
    result = JobSubmissionService.new(job_params).call

    if result.success?
      @job = result.job
      render :show, status: :created
    else
      render json: { error: result.error }, status: result.status
    end
  end

  private

  def job_params
    params.permit(:client_id, :priority, :workload, :idempotency_key)
  end
end
