class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :encrypted_password, null: false, default: ""
      t.string :first_name
      t.string :last_name
      t.jsonb :voice_signature_data
      t.jsonb :preferences, null: false, default: {}
      t.string :jti, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :jti, unique: true
  end
end
