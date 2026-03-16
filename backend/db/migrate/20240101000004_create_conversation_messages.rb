class CreateConversationMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_messages, id: :uuid do |t|
      t.references :voice_session, null: false, foreign_key: true, type: :uuid
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :tool_calls
      t.jsonb :tool_results
      t.integer :token_count
      t.integer :latency_ms

      t.timestamps
    end
  end
end
