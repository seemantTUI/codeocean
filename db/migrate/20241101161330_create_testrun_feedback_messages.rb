class CreateTestrunFeedbackMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :testrun_feedback_messages do |t|
      t.references :testrun, null: false, foreign_key: true
      t.text :feedback_message, null: false

      t.timestamps
    end
  end
end