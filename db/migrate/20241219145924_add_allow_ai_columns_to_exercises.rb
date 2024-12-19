# frozen_string_literal: true

class AddAllowAiColumnsToExercises < ActiveRecord::Migration[7.2]
  def change
    add_column :exercises, :allow_ai_comment_for_rfc, :boolean
    add_column :exercises, :allow_ai_feedback_on_score, :boolean
  end
end
