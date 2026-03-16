class CreateVehicles < ActiveRecord::Migration[7.1]
  def change
    create_table :vehicles, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :make
      t.string :model
      t.integer :year
      t.string :vin
      t.string :vehicle_type
      t.jsonb :integration_config, null: false, default: {}

      t.timestamps
    end

    add_index :vehicles, :vin, unique: true
  end
end
