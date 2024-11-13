# frozen_string_literal: true

class RequestForCommentsController < ApplicationController
  include CommonBehavior
  before_action :require_user!
  before_action :set_request_for_comment, only: %i[show mark_as_solved set_thank_you_note clear_question]
  before_action :set_study_group_grouping,
    only: %i[index my_comment_requests rfcs_with_my_comments rfcs_for_exercise]

  def authorize!
    authorize(@request_for_comments || @request_for_comment)
  end
  private :authorize!

  # GET /request_for_comments
  # GET /request_for_comments.json
  def index
    @search = ransack_search do |rfcs|
      # Only show RfCs for published exercises
      rfcs.where(exercises: {unpublished: false})
    end

    @request_for_comments = find_and_paginate_rfcs do |rfcs|
      # Order for the view (and subqueries)
      rfcs.order(created_at: :desc)
    end

    authorize!
  end


  # GET /my_request_for_comments
  def my_comment_requests
    @search = ransack_search do |rfcs|
      # Only show any RfC the user has created or any RfC for a submission of any programming group the user belongs to
      rfcs.joins(:submission)
        .where(user: current_user)
        .or(policy_scope(RequestForComment)
              .joins(:exercise)
              .joins(:submission)
              # Using the IDs here is much faster than using the polymorphic association.
              # This is because the association would result in a nested loop join.
              .where(submissions: {contributor_id: current_user.programming_group_ids}))
    end

    @request_for_comments = find_and_paginate_rfcs(per_user: nil) do |rfcs|
      # Order for the view (and subqueries)
      rfcs.order(created_at: :desc)
    end

    authorize!
    render 'index'
  end

  # GET /my_rfc_activity
  def rfcs_with_my_comments
    @search = ransack_search do |rfcs|
      # Only show RfCs with comments by the user
      rfcs.joins(:comments)
        .where(comments: {user: current_user})
    end

    @request_for_comments = find_and_paginate_rfcs(per_user: nil) do |rfcs|
      # Order for the view (and subqueries)
      rfcs.order(last_activity: :desc)
    end

    authorize!
    render 'index'
  end

  # GET /exercises/:id/request_for_comments
  def rfcs_for_exercise
    exercise = Exercise.find(params[:exercise_id])
    authorize(exercise)

    @search = ransack_search do |rfcs|
      # Only show RfCs belonging to the exercise
      rfcs.where(exercise:)
    end

    @request_for_comments = find_and_paginate_rfcs(per_user: nil) do |rfcs|
      # Order for the view (and subqueries)
      rfcs.order(last_activity: :desc)
    end

    render 'index'
  end

  # GET /request_for_comments/1/mark_as_solved
  def mark_as_solved
    authorize!
    @request_for_comment.solved = true
    respond_to do |format|
      if @request_for_comment.save
        format.json { render :show, status: :ok, location: @request_for_comment }
      else
        format.json { render json: @request_for_comment.errors, status: :unprocessable_content }
      end
    end
  end

  # POST /request_for_comments/1/set_thank_you_note
  def set_thank_you_note
    authorize!
    @request_for_comment.thank_you_note = params[:note]

    commenters = @request_for_comment.commenters
    commenters.each {|commenter| UserMailer.send_thank_you_note(@request_for_comment, commenter).deliver_later }

    respond_to do |format|
      if @request_for_comment.save
        format.json { render :show, status: :ok, location: @request_for_comment }
      else
        format.json { render json: @request_for_comment.errors, status: :unprocessable_content }
      end
    end
  end

  # POST /request_for_comments/1/clear_question
  def clear_question
    authorize!
    update_and_respond(object: @request_for_comment, params: {question: nil})
  end

  # GET /request_for_comments/1
  # GET /request_for_comments/1.json
  def show
    authorize!
  end


  def chat_with_ai
    @request_for_comment = RequestForComment.find(params[:id])
    authorize @request_for_comment # Ensure authorization

    # Fetch the conversation history for display
    @conversation_history = @request_for_comment.ai_conversation_histories.order(:created_at)

    # Helper to split messages into parts (text/code

    # Process the conversation history to include split messages
    @split_conversation = @conversation_history.map do |conversation|
      {
        role: conversation.role,
        parts: split_message(conversation.message)
      }
    end

    # Construct the initial prompt with exercise, file, and question information
    file = CodeOcean::File.find(@request_for_comment.file_id)
    question = @request_for_comment.question.presence || "The author did not enter a question for this request."
    constructed_prompt = construct_prompt(file, question)

    # Check if this is the first time or if the ai_response exists but conversation history hasn't been saved
    if @request_for_comment.ai_conversation_histories.where(role: 'system').blank?
      begin
        # Save the system message to the conversation history (constructed prompt)
        @request_for_comment.ai_conversation_histories.create!(
          message: constructed_prompt,
          role: 'system',
          user_id: current_user.id
        )

        # Check if ai_response is already present, if so, add it to the history
        # if @request_for_comment.ai_response.present? and @request_for_comment.ai_conversation_histories.where(role: 'assistant').blank?
        #   # Save the existing AI response to the conversation history
        #   @request_for_comment.ai_conversation_histories.create!(
        #     message: @request_for_comment.ai_response,
        #     role: 'assistant',
        #     user_id: current_user.id
        #   )
        # else if
        #   # Send the conversation history to ChatGPT and get the initial response
        #   messages = @request_for_comment.ai_conversation_histories.order(:created_at).map do |conversation|
        #     { role: conversation.role, content: conversation.message }
        #   end
        #
        #   gpt_service = ChatGptRequest.new
        #   @ai_response = gpt_service.request_gpt_with_history(messages)
        #
        #   # Save the AI's response to the conversation history
        #   @request_for_comment.ai_conversation_histories.create!(
        #     message: @ai_response,
        #     role: 'assistant',
        #     user_id: current_user.id
        #   )
        #
        #   # Save the response to the request_for_comment object
        #   @request_for_comment.update(ai_response: @ai_response)
        # end

        # Refresh the conversation history and process it
        @conversation_history = @request_for_comment.ai_conversation_histories.order(:created_at)
        @split_conversation = @conversation_history.map do |conversation|
          {
            role: conversation.role,
            parts: split_message(conversation.message)
          }
        end
      rescue => e
        # Handle any errors with the ChatGPT service
        @error = "There was an error processing your request: #{e.message}"
      end
    end

    # Check if the user provided a new prompt via the form
    prompt = params[:prompt]

    if prompt.present?
      begin
        # Save the user's prompt to the conversation history
        @request_for_comment.ai_conversation_histories.create!(
          message: prompt,
          role: 'user',
          user_id: current_user.id
        )

        # Prepare the conversation messages for ChatGPT
        messages = @request_for_comment.ai_conversation_histories.order(:created_at).map do |conversation|
          { role: conversation.role, content: conversation.message }
        end

        # Send the conversation history to ChatGPT and get a new response
        gpt_service = ChatGptRequest.new
        @ai_response = gpt_service.request_gpt_with_history(messages)

        # Save the AI's response to the conversation history
        @request_for_comment.ai_conversation_histories.create!(
          message: @ai_response,
          role: 'assistant',
          user_id: current_user.id
        )

        # Optionally update the latest AI response in the request_for_comment object
        @request_for_comment.update(ai_response: @ai_response)

        # Refresh the conversation history and process it
        @conversation_history = @request_for_comment.ai_conversation_histories.order(:created_at)
        @split_conversation = @conversation_history.map do |conversation|
          {
            role: conversation.role,
            parts: split_message(conversation.message)
          }
        end
      rescue => e
        # Handle any errors with the ChatGPT service
        @error = "There was an error processing your request: #{e.message}"
      end
    end

    # Render the chat_with_ai view
    render :chat_with_ai
  end
  def split_message(message)
    parts = message.split("```")
    parts.map.with_index do |part, index|
      { type: (index.even? ? 'text' : 'code'), content: part }
    end
  end







  # POST /request_for_comments.json
  def create
    # Consider all requests as JSON
    request.format = 'json'
    raise Pundit::NotAuthorizedError if @embed_options[:disable_rfc]

    @request_for_comment = RequestForComment.new(request_for_comment_params)

    respond_to do |format|
      if @request_for_comment.save
        begin
          # execute the tests here and wait until they finished.
          # As the same runner is used for the score and test run, no parallelization is possible
          # A run is triggered from the frontend and does not need to be handled here.
          @request_for_comment.submission.calculate_score(current_user)
          @request_for_comment.submission.files.select(&:user_defined_test?).each do |file|
            @request_for_comment.submission.test(file, current_user)
          end
        rescue Runner::Error::RunnerInUse => e
          Rails.logger.debug { "Scoring a submission failed because the runner was already in use: #{e.message}" }
          format.json { render json: {error: t('exercises.editor.runner_in_use'), status: :runner_in_use}, status: :conflict }
        rescue Runner::Error => e
          Rails.logger.debug { "Runner error while requesting comments: #{e.message}" }
          format.json { render json: {danger: t('exercises.editor.depleted'), status: :container_depleted}, status: :service_unavailable }
        else
          format.json { render :show, status: :created, location: @request_for_comment }
        end
      else
        format.html { render :new }
        format.json { render json: @request_for_comment.errors, status: :unprocessable_content }
      end
    end
    authorize!
  end

  private
  def send_to_chatgpt_and_create_comment(request_for_comment)
    submission = request_for_comment.submission
    file = submission.files.first

    # Send the question to ChatGPT and get the response
    gpt_service = ChatGptRequest.new
    begin
      gpt_response = gpt_service.request_gpt(request_for_comment)
      Comment.create!(
        text: gpt_response,
        file_id: file.id,
        row: '0',
        column: '0',
        user: current_user
      )
      flash[:notice] = "sucess" # Display success message
    rescue StandardError => e
      Rails.logger.debug { "Error creating comment or ChatGPT request failed: #{e.message}" }
      flash[:alert] = "error" # Display error message
      return # Stop further execution if it fails
      # params = {
      #   text: "gpt_response",
      #   file_id: file.id,
      #   row: '0',
      #   column: '0',
      #   user: current_user
      # }
      # redirect_to comments_path, method: :post, params: params
      # @request_for_comment.update(ai_response: gpt_response)
      # @request_for_comment.ai_conversation_histories.create!(
      #   message: @request_for_comment.ai_response,
      #   role: 'assistant',
      #   user_id: current_user.id
      # )
    end
  end


  # Use callbacks to share common setup or constraints between actions.
  def set_request_for_comment
    @request_for_comment = RequestForComment.includes(:exercise, :user, submission: [:study_group, {files: [:file_type], testruns: [:testrun_messages, {file: [:file_type]}]}]).find(params[:id])
  end


  def request_for_comment_params
    # The study_group_id might not be present in the session (e.g. for internal users), resulting in session[:study_group_id] = nil which is intended.
    params.require(:request_for_comment).permit(:exercise_id, :file_id, :question, :requested_at, :solved, :submission_id).merge(user: current_user)
  end

  # The index page requires the grouping of the study groups
  # The study groups are grouped by the current study group and other study groups of the user
  def set_study_group_grouping
    current_study_group = StudyGroup.find_by(id: session[:study_group_id])
    my_study_groups = case current_user.consumer.rfc_visibility
                        when 'all' then current_user.study_groups.order(name: :desc)
                        when 'consumer' then current_user.study_groups.where(consumer: current_user.consumer).order(name: :desc)
                        when 'study_group' then current_study_group.present? ? Array(current_study_group) : []
                        else raise "Unknown RfC Visibility #{current_user.consumer.rfc_visibility}"
                      end

    @study_groups_grouping = [[t('request_for_comments.index.study_groups.current'), Array(current_study_group)],
                              [t('request_for_comments.index.study_groups.my'), my_study_groups.reject {|group| group == current_study_group }]]
  end

  def ransack_search
    # The `policy_scope` is used to enforce the consumer's rfc_visibility setting.
    # This is defined through Pundit, see `RequestForCommentPolicy::Scope` in `policies/request_for_comment_policy.rb`.
    rfcs = policy_scope(RequestForComment)
      # The join is used for the where clause below but also ensures we are not showing RfCs without an exercise
      .joins(:exercise)

    # Allow the caller to apply additional conditions to the search.
    rfcs = yield rfcs if block_given?

    # Apply the actual search and sort options.
    # The sort options are applied, so that the resulting Ransack::Search object contains all desired options.
    # However, the actual sorting is deferred (through a call to `reorder(nil)`) and performed later.
    # Still, for the view helper, we need to store the sort options in the search object.
    rfcs.ransack(params[:q])
  end

  def ransack_sort
    # Extract the sort options from the params and apply them to a new ransack search.
    # This is used to apply the sort options to the search result *after* filtering the results.
    RequestForComment.ransack(s: params.dig(:q, :s))
  end

  def find_and_paginate_rfcs(per_user: 2)
    # 1. Get any sort options from the caller.
    # For convenience, the caller can provide these options as ActiveRecord::Relation query methods.
    desired_sort_options = yield RequestForComment if block_given?
    desired_sort_options = desired_sort_options&.arel&.orders

    # 2. Apply the filter options to the RfCs as specified by Ransack.
    matching_records_arel = RequestForComment.with_ransack_search_arel(@search)
    # 3. Get the last n RfCs per user. A value of `nil` for `per_user` means all RfCs.
    last_matching_records_arel = RequestForComment.with_last_per_user_arel(matching_records_arel, per_user)

    # 4. Apply the sort options to the RfCs and paginate the result set.
    # We need to sort first, since the pagination is applied to the sorted result set.
    # If the sort options include the `last_activity` attribute, we need to include it in the query.
    if desired_sort_options&.any? {|sort| sort.expr.to_s == '"last_activity"' }
      # Annotating RfCs with the last comment activity is an expensive operation, since it includes three joins.
      # Therefore, we only do this if the sort options include the `last_activity` attribute.
      annotated_last_matching_records_arel = RequestForComment.with_last_activity_arel(last_matching_records_arel)
      # On the resulting query, we apply the sort options as specified by Ransack the caller.
      sorted_last_matching_records_arel = RequestForComment.with_ransack_sort_arel(ransack_sort, desired_sort_options, annotated_last_matching_records_arel)
      # Now, we paginate the result set and need to convert it to an Arel query. This is necessary for compatibility with the `else` branch.
      annotated_final_result_set_arel = RequestForComment.from(sorted_last_matching_records_arel)
        .paginate(page: params[:page], per_page: per_page_param)
        .arel.as(RequestForComment.arel_table.name)
    else
      # Apply the sort options to the RfCs as specified by Ransack and the caller.
      sorted_last_matching_records_arel = RequestForComment.with_ransack_sort_arel(ransack_sort, desired_sort_options, last_matching_records_arel)
      # Now, we paginate the result set and simply extract the desired RfCs (their IDs, without the last comment activity).
      selected_request_for_comments = RequestForComment.from(sorted_last_matching_records_arel)
        .paginate(page: params[:page], per_page: per_page_param)
      # For the final result set, we need to include the last comment activity as a preparation for the view.
      # Since only `per_page_param` RfCs are selected, the performance impact is limited.
      final_result_set_arel = RequestForComment.with_id_arel(selected_request_for_comments)
      annotated_final_result_set_arel = RequestForComment.with_last_activity_arel(final_result_set_arel)
    end

    # 5. Manually apply compatibility with WillPaginate and prefetch the necessary associations.
    request_for_comments = RequestForComment.from(annotated_final_result_set_arel)
      .includes(submission: %i[study_group exercise contributor])
      .includes(:file, :comments, user: [:consumer])
      .extending(WillPaginate::ActiveRecord::RelationMethods)

    # 6. Apply the sort options to **current page** of the result set.
    # This is needed since the sorting is not kept when annotating the result set with the last comment activity.
    # (We're grouping by the RfC attributes and the last comment activity.)
    if ransack_sort.result.arel.join_sources.present?
      request_for_comments = request_for_comments.joins(*ransack_sort.result.arel.join_sources)
        .order(*ransack_sort.result.arel.orders)
    end

    # 7. Similarly to the Ransack sort, we also need to reapply the sort options from the caller.
    if desired_sort_options.present?
      request_for_comments = request_for_comments.order(*desired_sort_options)
    end

    # 8. We need to manually enable the pagination links.
    request_for_comments.current_page = WillPaginate::PageNumber(params[:page] || 1)
    request_for_comments.limit_value = per_page_param
    request_for_comments.total_entries = RequestForComment.from(last_matching_records_arel).count

    # Debugging: Print the SQL query to the console.
    Rails.logger.debug { request_for_comments.to_sql }

    # Return the paginated, sorted result set.
    request_for_comments
  end
end
