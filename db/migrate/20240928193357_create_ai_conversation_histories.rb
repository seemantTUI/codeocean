class CreateAiConversationHistories < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_conversation_histories, id: :uuid do |t|
      t.references :request_for_comment, null: false, foreign_key: true
      t.text :message
      t.string :role
      t.integer :user_id, null: false

      t.timestamps
    end
  end
end
