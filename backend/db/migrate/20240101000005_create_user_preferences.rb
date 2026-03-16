class CreateUserPreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :user_preferences, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.float :voice_speed, default: 1.0
      t.string :voice_name, default: "samantha"
      t.string :language, default: "en-US"
      t.string :response_verbosity, default: "concise"
      t.string :safety_level, default: "standard"
      t.jsonb :custom_settings, null: false, default: {}

      t.timestamps
    end

    add_index :user_preferences, :user_id, unique: true
  end
end
