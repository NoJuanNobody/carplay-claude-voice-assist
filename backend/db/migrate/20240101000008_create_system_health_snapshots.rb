class CreateSystemHealthSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :system_health_snapshots, id: :uuid do |t|
      t.string :service_name, null: false
      t.string :status, null: false
      t.integer :response_time_ms
      t.integer :error_count, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.datetime :recorded_at, null: false

      t.timestamps
    end
  end
end
