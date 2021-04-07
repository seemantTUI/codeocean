# frozen_string_literal: true

class Runner
  BASE_URL = CodeOcean::Config.new(:code_ocean).read[:runner_management][:url]
  HEADERS = {'Content-Type' => 'application/json'}.freeze

  attr_accessor :waiting_time

  def initialize(execution_environment, time_limit = nil)
    url = "#{BASE_URL}/runners"
    body = {executionEnvironmentId: execution_environment.id}
    body[:timeLimit] = time_limit if time_limit
    response = Faraday.post(url, body.to_json, HEADERS)
    response = parse response
    @id = response[:runnerId]
  end

  def copy_files(files)
    url = "#{runner_url}/files"
    body = {files: files.map { |filename, content| {filepath: filename, content: content} }}
    Faraday.patch(url, body.to_json, HEADERS)
  end

  def execute_command(command)
    url = "#{runner_url}/execute"
    response = Faraday.post(url, {command: command}.to_json, HEADERS)
    parse response
  end

  def execute_interactively(command)
    starting_time = Time.zone.now
    websocket_url = execute_command(command)[:websocketUrl]
    EventMachine.run do
      socket = RunnerConnection.new(websocket_url)
      yield(self, socket) if block_given?
    end
    Time.zone.now - starting_time # execution time
  end

  def destroy
    Faraday.delete runner_url
  end

  def status
    # TODO: return actual state retrieved via websocket
    :timeouted
  end

  private

  def runner_url
    "#{BASE_URL}/runners/#{@id}"
  end

  def parse(response)
    JSON.parse(response.body).deep_symbolize_keys
  end
end
