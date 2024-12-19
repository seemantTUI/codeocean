# frozen_string_literal: true

class ChangeAllowAiColumnsInExercises < ActiveRecord::Migration[7.2]
  def change
    change_column :exercises, :allow_ai_comment_for_rfc, :boolean, null: false, default: false
    change_column :exercises, :allow_ai_feedback_on_score, :boolean, null: false, default: false
  end
end
