# frozen_string_literal: true

FactoryBot.define do
  factory :submission do
    cause { 'save' }
    created_by_external_user
    exercise factory: :math

    after(:create) do |submission|
      submission.exercise.files.editable.visible.each do |file|
        submission.add_file(content: file.content, file_id: file.id)
      end
    end
  end
end
