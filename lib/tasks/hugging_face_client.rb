class HuggingFaceClient
  require 'net/http'
  require 'uri'
  require 'json'

  def initialize
    @api_key = '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'
    unless @api_key
      raise "API key is missing."
    end
  end

  def chat_completion(messages, model: 'meta-llama/Llama-3.2-3B-Instruct', max_tokens: 500)
    url = URI.parse("https://api-inference.huggingface.co/models/#{model}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@api_key}"
    }

    body = {
      inputs: messages,
      parameters: {
        max_tokens: max_tokens,
        stream: true
      }
    }

    request = Net::HTTP::Post.new(url.path, headers)
    request.body = body.to_json

    response = http.request(request)
    Rails.logger.debug "ChatGPT Raw Response: #{response.body}"

    json_response = JSON.parse(response.body)
    return json_response
  rescue => e
    puts "Request failed: #{e.message}"
  end
end

