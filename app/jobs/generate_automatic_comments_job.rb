# app/jobs/generate_automatic_comments_job.rb
class GenerateAutomaticCommentsJob < ApplicationJob
  queue_as :default
  def perform(request_for_comment, current_user)
    chat_gpt_user = InternalUser.find_by(email: 'chatgpt@example.org')
    chat_gpt_service = ChatGptService::ChatGptRequest.new
    chat_gpt_disclaimer = I18n.t('exercises.editor.chat_gpt_disclaimer')
    request_for_comment.submission.files.each do |file|
      response_data = chat_gpt_service.get_response(
        request_for_comment: request_for_comment,
        file: file,
        response_format_needed: true
      )
      Rails.logger.debug "Response data: #{response_data.inspect}"
      next unless response_data.present?

      # Create comment for combined 'requirements' comments
      if response_data[:requirements_comments].present?
        Rails.logger.debug "Requirements comments found."
        comment = create_comment(
          text: "#{response_data[:requirements_comments]}\n\n#{chat_gpt_disclaimer}",
          file_id: file.id,
          row: '0',
          column: '0',
          user: chat_gpt_user
        )
        send_emails(comment, request_for_comment, current_user, chat_gpt_user) if comment.persisted?
      end

      # Create comments for each line-specific comment
      response_data[:line_specific_comments].each do |line_comment_data|
        create_comment(
          text: "#{line_comment_data[:comment]}\n\n#{chat_gpt_disclaimer}",
          file_id: file.id,
          row: line_comment_data[:line_number].to_s,
          column: '0',
          user: chat_gpt_user
        )
      end
    end
  end

  private

  def create_comment(attributes)
    Comment.create(
      text: attributes[:text],
      file_id: attributes[:file_id],
      row: attributes[:row],
      column: attributes[:column],
      user: attributes[:user]
    )
  end

  def send_emails(comment, request_for_comment, current_user, chat_gpt_user)
    send_mail_to_author(comment, request_for_comment, chat_gpt_user)
    send_mail_to_subscribers(comment, request_for_comment, current_user)
  end

  def send_mail_to_author(comment, request_for_comment, chat_gpt_user)
    if chat_gpt_user == comment.user
      UserMailer.got_new_comment(comment, request_for_comment, chat_gpt_user).deliver_later
    end
  end

  def send_mail_to_subscribers(comment, request_for_comment, current_user)
    request_for_comment.commenters.each do |commenter|
      subscriptions = Subscription.where(
        request_for_comment_id: request_for_comment.id,
        user: commenter,
        deleted: false
      )
      subscriptions.each do |subscription|
        next if subscription.user == current_user

        should_send = (subscription.subscription_type == 'author' && current_user == request_for_comment.user) ||
          (subscription.subscription_type == 'all')

        if should_send
          UserMailer.got_new_comment_for_subscription(comment, subscription, current_user).deliver_later
          break
        end
      end
    end
  end
end
