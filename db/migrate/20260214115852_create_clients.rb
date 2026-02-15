class CreateClients < ActiveRecord::Migration[7.0]
  def change
    create_table :clients do |t|
      t.string :name, null: false
      t.integer :concurrency_limit, null: false, default: 1

      t.timestamps
    end

    add_index :clients, :name, unique: true
  end
end
