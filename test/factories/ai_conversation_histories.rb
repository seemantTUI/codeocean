FactoryBot.define do
  factory :ai_conversation_history do
    request_for_comment { nil }
    message { "MyText" }
    role { "MyString" }
    user { nil }
  end
end
