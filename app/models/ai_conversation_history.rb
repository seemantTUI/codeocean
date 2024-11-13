class AiConversationHistory < ApplicationRecord
  belongs_to :request_for_comment

  # No association with User model since we're storing user_id as a string
  # Optionally, add validation if user_id should always be present for user messages
  validates :user_id, presence: true, if: -> { role == 'user' }

  validates :message, presence: true
  validates :role, presence: true
end