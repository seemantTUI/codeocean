FactoryGirl.define do
  #TODO do this proper
  factory :lti_parameter do
    consumers_id 1
    exercises_id 1
    external_users_id 1

    lti_parameters JSON.parse('{"lis_result_sourcedid": "c2db0c7c-4411-4b27-a52b-ddfc3dc32065",
                              "lis_outcome_service_url": "http://172.16.54.235:3000/courses/0132156a-9afb-434d-83cc-704780104105/sections/21c6c6f4-1fb6-43b4-af3c-04fdc098879e/items/999b1fe6-d4b6-47b7-a577-ea2b4b1041ec/tool_grading",
                              "launch_presentation_return_url": "http://172.16.54.235:3000/courses/0132156a-9afb-434d-83cc-704780104105/sections/21c6c6f4-1fb6-43b4-af3c-04fdc098879e/items/999b1fe6-d4b6-47b7-a577-ea2b4b1041ec/tool_return"}')
  end

  # factory :lti_parameter do
  #   association :consumers_id, factory: :consumer
  #   association :exercises_id, factory: :math
  #   association :external_users_id, factory: :external_user
  #
  #
  #   trait :lti_parameters do
  #     JSON.parse('{"lis_result_sourcedid": "c2db0c7c-4411-4b27-a52b-ddfc3dc32065", "lis_outcome_service_url": "http://172.16.54.235:3000/courses/0132156a-9afb-434d-83cc-704780104105/sections/21c6c6f4-1fb6-43b4-af3c-04fdc098879e/items/999b1fe6-d4b6-47b7-a577-ea2b4b1041ec/tool_grading", "launch_presentation_return_url": "http://172.16.54.235:3000/courses/0132156a-9afb-434d-83cc-704780104105/sections/21c6c6f4-1fb6-43b4-af3c-04fdc098879e/items/999b1fe6-d4b6-47b7-a577-ea2b4b1041ec/tool_return"}')
  #   end
  # end
end