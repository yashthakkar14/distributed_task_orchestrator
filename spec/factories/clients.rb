FactoryBot.define do
  factory :client do
    sequence(:name) { |n| "client_#{n}" }
    concurrency_limit { 3 }
  end
end
