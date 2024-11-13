class TestrunFeedbackMessageController < ApplicationController
  def show
    testrun_feedback_message = TestrunFeedbackMessage.find_by(testrun_id: params[:testrun_id])

    if testrun_feedback_message
      render plain: testrun_feedback_message.feedback_message
    else
      render plain: "No feedback available for this test run.", status: :not_found
    end
  end
end