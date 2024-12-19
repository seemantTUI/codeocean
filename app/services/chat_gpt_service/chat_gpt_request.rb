require 'net/http'
require 'uri'
require 'json'

module ChatGptService
  class ChatGptRequest
    API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
    MODEL_NAME = 'gpt-4o'.freeze
    def initialize
      @api_key = Rails.application.credentials.openai[:api_key]
      unless @api_key
        raise "OpenAI API key is missing. Please set it in environment variables or Rails credentials."
      end
    end

    def get_response(options = {})
      prompt = construct_prompt(options)
      response = make_chat_gpt_request(prompt, options[:response_format_needed])
      if options[:response_format_needed]
        format_response(response)
      else
        response
      end
    end

    private

    def construct_prompt(options)
      if options[:request_for_comment] && options[:file]
        construct_prompt_for_rfc(options[:request_for_comment], options[:file])
      else
        format_prompt(options)
      end
    end

    def construct_prompt_for_rfc(request_for_comment, file)
      submission = request_for_comment.submission
      test_run_results = Testrun.where(submission_id: submission.id).map(&:log).join("\n")
      options = {
        learner_solution: file.content,
        exercise: submission.exercise.description,
        test_results: test_run_results,
        question: request_for_comment.question
      }
      format_prompt(options)
    end

    def format_prompt(options)
      if I18n.locale == :en
        file_path = Rails.root.join('app', 'services/chat_gpt_service/chat_gpt_prompts', 'prompt_en.xml')
        prompt = File.read(file_path)
        prompt.gsub!("[Learner's Code]", options[:learner_solution] || "")
        prompt.gsub!("[Task]", options[:exercise] || "")
        prompt.gsub!("[Error Message]", options[:test_results] || "")
        prompt.gsub!("[Student Question]", options[:question] || "")
      else
        file_path = Rails.root.join('app', 'services/chat_gpt_service/chat_gpt_prompts', 'prompt_de.xml')
        prompt = File.read(file_path)
        prompt.gsub!("[Code des Lernenden]", options[:learner_solution] || "")
        prompt.gsub!("[Aufgabenstellung]", options[:exercise] || "")
        prompt.gsub!("[Fehlermeldung]", options[:test_results] || "")
        prompt.gsub!("[Frage des Studierenden]", options[:question] || "")
      end

      prompt
    end

    def make_chat_gpt_request(prompt, response_format_needed = false)
      url = URI.parse(API_URL)
      data = {
        model: MODEL_NAME,
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 2048
      }
      if response_format_needed
        response_format = JSON.parse(File.read(Rails.root.join('app', 'services/chat_gpt_service/chat_gpt_prompts', 'response_format.json')))
        data[:response_format] = response_format
      end

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(url.path, {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      })
      request.body = data.to_json

      begin
        response = http.request(request)
        json_response = JSON.parse(response.body)

        if response.is_a?(Net::HTTPSuccess)
          json_response.dig('choices', 0, 'message', 'content')
        else
          error_message = json_response.dig('error', 'message') || 'Unknown error'
          Rails.logger.error "ChatGPT API Error: #{error_message}"
          raise "ChatGPT API Error: #{error_message}"
        end
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse ChatGPT response: #{e.message}"
        raise "Failed to parse ChatGPT response: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Error while making request to ChatGPT: #{e.message}"
        raise e
      end
    end

    def format_response(response)
      parsed_response = JSON.parse(response)
      requirements_comments = ''
      if parsed_response['requirements']
        requirements_comments = parsed_response['requirements'].map { |req| req['comment'] }.join("\n")
      end

      line_specific_comments = []
      if parsed_response['line_specific_comments']
        line_specific_comments = parsed_response['line_specific_comments'].map do |line_comment|
          {
            line_number: line_comment['line_number'],
            comment: line_comment['comment']
          }
        end
      end

      {
        requirements_comments: requirements_comments,
        line_specific_comments: line_specific_comments
      }
    end
  end
end