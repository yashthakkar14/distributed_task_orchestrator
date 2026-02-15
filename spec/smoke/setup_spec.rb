require 'rails_helper'

RSpec.describe 'Project Setup', type: :smoke do
  describe 'Rails application' do
    it 'loads successfully' do
      expect(Rails.application).to be_a(Rails::Application)
      expect(Rails.application.class.name).to eq('JobOrchestrator::Application')
    end

    it 'is configured as API-only' do
      expect(Rails.application.config.api_only).to be true
    end
  end

  describe 'Database connection' do
    it 'connects to MySQL' do
      expect(ActiveRecord::Base.connection).to be_active
    end

    it 'uses the mysql2 adapter' do
      expect(ActiveRecord::Base.connection.adapter_name).to eq('Mysql2')
    end
  end

  describe 'Redis connection' do
    it 'responds to PING' do
      expect(REDIS.ping).to eq('PONG')
    end
  end

  describe 'Sidekiq' do
    it 'is configured' do
      expect(defined?(Sidekiq)).to be_truthy
    end
  end
end
