# Create test clients with different concurrency limits
clients = [
  { name: 'client_alpha', concurrency_limit: 3 },
  { name: 'client_beta', concurrency_limit: 2 },
  { name: 'client_gamma', concurrency_limit: 5 }
]

clients.each do |attrs|
  Client.find_or_create_by!(name: attrs[:name]) do |c|
    c.concurrency_limit = attrs[:concurrency_limit]
  end
end

puts "Created #{Client.count} clients"
