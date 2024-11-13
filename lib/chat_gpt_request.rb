class ChatGptRequest
  require 'net/http'
  require 'uri'
  require 'json'

  API_URL = 'https://api.openai.com/v1/chat/completions'.freeze
  MODEL_NAME = 'gpt-4'.freeze

  PROMPT_TEMPLATE = <<~PROMPT
<prompt>
    <case>
        1-1 Syntax Error - Beginner
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>Your task is to formulate a hint for the learner's code, delimited by """.</instruction_1>
        <instruction_2>The hint you generate must meet each requirement delimited by ###.</instruction_2>
        <instruction_3>The hint you generate should, to fulfill requirements 7, 8, and 9, take into account the task of the programming assignment, which is delimited by %%%.</instruction_3>
        <instruction_4>The hint you generate should, to fulfill requirement 10, definitely take into account the error message that the code caused. This error message is delimited by $$$.</instruction_4>
        <instruction_5>Requirements 6, 7, 8, 9, 10, 11, and 12 should each be met in their own separate paragraph in the hint.</instruction_5>
        <instruction_6>Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!</instruction_6>
        <instruction_7>The hint must answer the question asked by the student. The question is delimited by ???.</instruction_7>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback>
            6. The hint must contain a description or indication of the correct solution. This part should be marked with "(1)" in your hint. This part should describe where something should be in the code without giving a code example. Your hint should relate specifically to the problematic part of the code! Do not describe the error, but the correct solution!
        </requirement_KCR-feedback>
        <requirement_KTC-TR-feedback>
            7. The hint must contain rules, restrictions, or requirements of the task – in the form of hints to requirements in the task. This part should be marked with "(2)" in your hint. Only mention task requirements that directly relate to the code error! Do not mention unrelated requirements!
        </requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback>
            8. The hint must contain conceptual knowledge needed for the task – in the form of explanations of fundamental task concepts. This part should be marked with "(3)" in your hint.
        </requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback>
            9. The hint must contain conceptual knowledge needed for the task – in the form of examples that clarify fundamental concepts of the task. This part should be marked with "(4)" in your hint. Refer to the concept you selected in response to requirement number 8. Provide an original, specific example implementing the fundamental concept that does not relate to the current programming task! Be sure to include a code snippet to support your example!
        </requirement_KC-EXA-feedback>
        <requirement_KM-feedback>
            10. The hint must describe compiler or interpreter errors. Compiler or interpreter errors are syntax errors (incorrect spelling, missing brackets). This part should be marked with "(5)" in your hint. Provide a detailed explanation of the error itself, without steps to fix it.
        </requirement_KM-feedback>
        <requirement_KH-EC-feedback>
            11. The hint must contain knowledge about the learner's next steps for resolving this type of error. Relate this to fixing the kind of error present! This part should be marked with "(6)" in your hint. Explain the general steps the learner can take next, without showing the exact solution to the error, such as “Change this in line X”! Instead, provide general steps like: “Research this topic online,” “Learn more about this,” “Adjust your code accordingly,” or “Test the output of your code.”
        </requirement_KH-EC-feedback>
        <requirement_12>Provide each line-specific comment in xml in a new line using the format "Line [number]: [comment]".</requirement_12>
    </requirements>
    <input>
        <code name="Learner's Code" type="string">
            <delimiter>"""</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name="Task" type="string">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name="Error Message" type="string">
            <delimiter>$$$</delimiter>
            <description>Error message caused by the code:</description>
            <content>[Error Message]</content>
        </error_message>
        <student_question name="Student Question" type="string">
            <delimiter>???</delimiter>
            <description>Question asked by the student:</description>
            <content>[Student Question]</content>
        </student_question>
    </input>
</prompt>
PROMPT



  def initialize
    @api_key = ''
    unless @api_key
      raise "OpenAI API key is missing. Please set it in environment variables or Rails credentials."
    end
  end

  def request_gpt(request_for_comment)
    prompt = construct_prompt(request_for_comment)
    gpt_response(prompt)
  end

  private

  def gpt_response(prompt)
    url = URI.parse(API_URL)
    data = {
      model: MODEL_NAME,
      messages: [{ role: 'system', content: prompt }]
    }

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

  def construct_prompt(request_for_comment)
    submission = request_for_comment.submission
    test_run_results = Testrun.where(submission_id: submission.id).map(&:log).join("\n")
    format_prompt(submission, test_run_results, request_for_comment.question)
  end

  def format_prompt(submission, test_run_results, question)
    if I18n.locale == :en
      file_path = '/Users/seemantsingh/codeocean/app/chatgpt_prompts/Beginner_Syntax_en.xml'
    else
      file_path = '/Users/seemantsingh/codeocean/app/chatgpt_prompts/Beginner_Syntax_de.xml'
    end
    prompt = File.read(file_path)

    prompt.gsub!("[Learner's Code]", submission.files.first.content || "")
    prompt.gsub!("[Task]", submission.exercise.description || "[Task]")
    prompt.gsub!("[Error Message]", test_run_results || "")
    prompt.gsub!("[Student Question]", question || "")
    prompt
  end
end
