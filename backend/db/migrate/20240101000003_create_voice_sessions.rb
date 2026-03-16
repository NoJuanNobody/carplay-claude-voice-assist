class CreateVoiceSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :voice_sessions, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :vehicle, foreign_key: true, type: :uuid
      t.string :session_token, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.string :driving_state, default: "unknown"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :voice_sessions, :session_token, unique: true
  end
end
