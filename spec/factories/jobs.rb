FactoryBot.define do
  factory :job do
    client
    workload { "simulated_task_#{SecureRandom.hex(4)}" }
    priority { :medium }
    status { :queued }
  end
end
