class Client < ApplicationRecord
  has_many :jobs, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :concurrency_limit, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
end
