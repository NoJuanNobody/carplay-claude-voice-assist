class CreateIntegrationCredentials < ActiveRecord::Migration[7.1]
  def change
    create_table :integration_credentials, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :service_name, null: false
      t.text :encrypted_token
      t.datetime :expires_at
      t.jsonb :scopes, null: false, default: []

      t.timestamps
    end

    add_index :integration_credentials, %i[user_id service_name], unique: true
  end
end
