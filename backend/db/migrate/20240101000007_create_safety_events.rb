class CreateSafetyEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :safety_events, id: :uuid do |t|
      t.references :voice_session, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :event_type, null: false
      t.string :severity, null: false
      t.jsonb :details, null: false, default: {}
      t.string :driving_state_at_event
      t.datetime :resolved_at

      t.timestamps
    end
  end
end
