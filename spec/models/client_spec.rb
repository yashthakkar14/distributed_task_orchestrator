require 'rails_helper'

RSpec.describe Client, type: :model do
  describe 'associations' do
    it { should have_many(:jobs).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    subject { Client.new(name: 'test_client', concurrency_limit: 3) }

    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).case_insensitive }
    it { should validate_presence_of(:concurrency_limit) }
    it { should validate_numericality_of(:concurrency_limit).only_integer.is_greater_than(0) }
  end

  describe 'concurrency_limit' do
    it 'defaults to 1' do
      client = Client.create!(name: 'default_client')
      expect(client.concurrency_limit).to eq(1)
    end

    it 'rejects zero or negative values' do
      client = Client.new(name: 'bad_client', concurrency_limit: 0)
      expect(client).not_to be_valid
      expect(client.errors[:concurrency_limit]).to be_present
    end
  end
end
