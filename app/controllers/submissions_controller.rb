# frozen_string_literal: true

class SubmissionsController < ApplicationController
  include ActionController::Live
  include CommonBehavior
  include Lti
  include SubmissionParameters
  include Tubesock::Hijack

  before_action :require_user!
  before_action :set_submission, only: %i[download download_file render_file run score show statistics test]
  before_action :set_testrun, only: %i[run score test]
  before_action :set_files, only: %i[download show]
  before_action :set_files_and_specific_file, only: %i[download_file render_file run test]
  before_action :set_mime_type, only: %i[download_file render_file]
  skip_before_action :verify_authenticity_token, only: %i[download_file render_file]

  def create
    @submission = Submission.new(submission_params)
    authorize!
    create_and_respond(object: @submission)
  end

  def download
    raise Pundit::NotAuthorizedError if @embed_options[:disable_download]

    id_file = create_remote_evaluation_mapping

    stringio = Zip::OutputStream.write_buffer do |zio|
      @files.each do |file|
        zio.put_next_entry(file.filepath)
        zio.write(file.content.presence || file.native_file.read)
      end

      # zip exercise description
      zio.put_next_entry("#{t('activerecord.models.exercise.one')}.txt")
      zio.write("#{@submission.exercise.title}\r\n======================\r\n")
      zio.write(@submission.exercise.description)

      # zip .co file
      zio.put_next_entry('.co')
      zio.write(File.read(id_file))
      FileUtils.rm_rf(id_file)

      # zip client scripts
      scripts_path = 'app/assets/remote_scripts'
      Dir.foreach(scripts_path) do |file|
        next if (file == '.') || (file == '..')

        zio.put_next_entry(File.join('.scripts', File.basename(file)))
        zio.write(File.read(File.join(scripts_path, file)))
      end
    end
    send_data(stringio.string, filename: "#{@submission.exercise.title.tr(' ', '_')}.zip")
  end

  def download_file
    raise Pundit::NotAuthorizedError if @embed_options[:disable_download]

    if @file.native_file?
      send_file(@file.native_file.path)
    else
      send_data(@file.content, filename: @file.name_with_extension)
    end
  end

  def index
    @search = Submission.ransack(params[:q])
    @submissions = @search.result.includes(:exercise, :user).paginate(page: params[:page], per_page: per_page_param)
    authorize!
  end

  def render_file
    if @file.native_file?
      send_file(@file.native_file.path, disposition: 'inline')
    else
      render(plain: @file.content)
    end
  end

  def run
    # These method-local socket variables are required in order to use one socket
    # in the callbacks of the other socket. As the callbacks for the client socket
    # are registered first, the runner socket may still be nil.
    client_socket, runner_socket = nil

    hijack do |tubesock|
      client_socket = tubesock

      client_socket.onopen do |_event|
        kill_client_socket(client_socket) if @embed_options[:disable_run]
      end

      client_socket.onclose do |_event|
        runner_socket&.close(:terminated_by_client)
        @testrun[:status] ||= :terminated_by_client
      end

      client_socket.onmessage do |raw_event|
        # Obviously, this is just flushing the current connection: Filtering.
        next if raw_event == "\n"

        # Otherwise, we expect to receive a JSON: Parsing.
        event = JSON.parse(raw_event).deep_symbolize_keys
        event[:cmd] = event[:cmd].to_sym
        event[:stream] = event[:stream].to_sym if event.key? :stream

        # We could store the received event. However, it is also echoed by the container
        # and correctly identified as the original input. Therefore, we don't store
        # it here to prevent duplicated events.
        # @testrun[:messages].push(event)

        case event[:cmd]
          when :client_kill
            @testrun[:status] = :terminated_by_client
            close_client_connection(client_socket)
            Rails.logger.debug('Client exited container.')
          when :result, :canvasevent, :exception
            # The client cannot send something before the runner connection is established.
            if runner_socket.present?
              runner_socket.send_data raw_event
            else
              Rails.logger.info("Could not forward data from client because runner connection was not established yet: #{event[:data].inspect}")
            end
          else
            Rails.logger.info("Unknown command from client: #{event[:cmd]}")
            Sentry.set_extras(event: event)
            Sentry.capture_message("Unknown command from client: #{event[:cmd]}")
        end
      rescue JSON::ParserError => e
        Rails.logger.info("Data received from client is not valid json: #{raw_event.inspect}")
        Sentry.set_extras(data: raw_event)
        Sentry.capture_exception(e)
      rescue TypeError => e
        Rails.logger.info("JSON data received from client cannot be parsed as hash: #{raw_event.inspect}")
        Sentry.set_extras(data: raw_event)
        Sentry.capture_exception(e)
      end
    end

    @testrun[:output] = +''
    durations = @submission.run(@file) do |socket, starting_time|
      runner_socket = socket
      @testrun[:starting_time] = starting_time
      client_socket.send_data JSON.dump({cmd: :status, status: :container_running})

      runner_socket.on :stdout do |data|
        message = retrieve_message_from_output data, :stdout
        @testrun[:output] << message[:data][0, max_output_buffer_size - @testrun[:output].size] if message[:data]
        send_and_store client_socket, message
      end

      runner_socket.on :stderr do |data|
        message = retrieve_message_from_output data, :stderr
        @testrun[:output] << message[:data][0, max_output_buffer_size - @testrun[:output].size] if message[:data]
        send_and_store client_socket, message
      end

      runner_socket.on :exit do |exit_code|
        @testrun[:exit_code] = exit_code
        exit_statement =
          if @testrun[:output].empty? && exit_code.zero?
            @testrun[:status] = :ok
            t('exercises.implement.no_output_exit_successful', timestamp: l(Time.zone.now, format: :short), exit_code: exit_code)
          elsif @testrun[:output].empty?
            @testrun[:status] = :failed
            t('exercises.implement.no_output_exit_failure', timestamp: l(Time.zone.now, format: :short), exit_code: exit_code)
          elsif exit_code.zero?
            @testrun[:status] = :ok
            "\n#{t('exercises.implement.exit_successful', timestamp: l(Time.zone.now, format: :short), exit_code: exit_code)}"
          else
            @testrun[:status] = :failed
            "\n#{t('exercises.implement.exit_failure', timestamp: l(Time.zone.now, format: :short), exit_code: exit_code)}"
          end
        send_and_store client_socket, {cmd: :write, stream: :stdout, data: "#{exit_statement}\n"}
        if exit_code == 137
          send_and_store client_socket, {cmd: :status, status: :out_of_memory}
          @testrun[:status] = :out_of_memory
        end

        close_client_connection(client_socket)
      end
    end
    @testrun[:container_execution_time] = durations[:execution_duration]
    @testrun[:waiting_for_container_time] = durations[:waiting_duration]
  rescue Runner::Error::ExecutionTimeout => e
    send_and_store client_socket, {cmd: :status, status: :timeout}
    close_client_connection(client_socket)
    Rails.logger.debug { "Running a submission timed out: #{e.message}" }
    @testrun[:status] ||= :timeout
    @testrun[:output] = "timeout: #{@testrun[:output]}"
    extract_durations(e)
  rescue Runner::Error => e
    send_and_store client_socket, {cmd: :status, status: :container_depleted}
    close_client_connection(client_socket)
    @testrun[:status] ||= :container_depleted
    Rails.logger.debug { "Runner error while running a submission: #{e.message}" }
    extract_durations(e)
  ensure
    save_testrun_output 'run'
  end

  def score
    hijack do |tubesock|
      tubesock.onopen do |_event|
        switch_locale do
          kill_client_socket(tubesock) if @embed_options[:disable_score]

          # The score is stored separately, we can forward it to the client immediately
          tubesock.send_data(JSON.dump(@submission.calculate_score))
          # To enable hints when scoring a submission, uncomment the next line:
          # send_hints(tubesock, StructuredError.where(submission: @submission))
          kill_client_socket(tubesock)
        rescue Runner::Error => e
          extract_durations(e)
          send_and_store tubesock, {cmd: :status, status: :container_depleted}
          kill_client_socket(tubesock)
          Rails.logger.debug { "Runner error while scoring submission #{@submission.id}: #{e.message}" }
          @testrun[:passed] = false
          save_testrun_output 'assess'
        end
      end
    end
  end

  def show; end

  def statistics; end

  def test
    hijack do |tubesock|
      tubesock.onopen do |_event|
        switch_locale do
          kill_client_socket(tubesock) if @embed_options[:disable_run]

          # The score is stored separately, we can forward it to the client immediately
          tubesock.send_data(JSON.dump(@submission.test(@file)))
          kill_client_socket(tubesock)
        rescue Runner::Error => e
          extract_durations(e)
          send_and_store tubesock, {cmd: :status, status: :container_depleted}
          kill_client_socket(tubesock)
          Rails.logger.debug { "Runner error while testing submission #{@submission.id}: #{e.message}" }
          @testrun[:passed] = false
          save_testrun_output 'assess'
        end
      end
    end
  end

  private

  def authorize!
    authorize(@submission || @submissions)
  end

  def close_client_connection(client_socket)
    # search for errors and save them as StructuredError (for scoring runs see submission.rb)
    errors = extract_errors
    send_hints(client_socket, errors)
    kill_client_socket(client_socket)
  end

  def kill_client_socket(client_socket)
    # We don't want to store this (arbitrary) exit command and redirect it ourselves
    client_socket.send_data JSON.dump({cmd: :exit})
    client_socket.close
  end

  def create_remote_evaluation_mapping
    user = @submission.user
    exercise_id = @submission.exercise_id

    remote_evaluation_mapping = RemoteEvaluationMapping.create(
      user: user,
      exercise_id: exercise_id,
      study_group_id: session[:study_group_id]
    )

    # create .co file
    path = "tmp/#{user.id}.co"
    # parse validation token
    content = "#{remote_evaluation_mapping.validation_token}\n"
    # parse remote request url
    content += "#{evaluate_url}\n"
    @submission.files.each do |file|
      content += "#{file.filepath}=#{file.file_id}\n"
    end
    File.write(path, content)
    path
  end

  def extract_durations(error)
    @testrun[:starting_time] = error.starting_time
    @testrun[:container_execution_time] = error.execution_duration
    @testrun[:waiting_for_container_time] = error.waiting_duration
  end

  def extract_errors
    results = []
    if @testrun[:output].present?
      @submission.exercise.execution_environment.error_templates.each do |template|
        pattern = Regexp.new(template.signature).freeze
        results << StructuredError.create_from_template(template, @testrun[:output], @submission) if pattern.match(@testrun[:output])
      end
    end
    results
  end

  def send_and_store(client_socket, message)
    message[:timestamp] = if @testrun[:starting_time]
                            ActiveSupport::Duration.build(Time.zone.now - @testrun[:starting_time])
                          else
                            0.seconds
                          end
    @testrun[:messages].push message
    @testrun[:status] = message[:status] if message[:status]
    client_socket.send_data JSON.dump(message)
  end

  def max_output_buffer_size
    if @submission.cause == 'requestComments'
      5000
    else
      500
    end
  end

  def sanitize_filename
    params[:filename].gsub(/\.json$/, '')
  end

  # save the output of this "run" as a "testrun" (scoring runs are saved in submission.rb)
  def save_testrun_output(cause)
    testrun = Testrun.create!(
      file: @file,
      passed: @testrun[:passed],
      cause: cause,
      submission: @submission,
      exit_code: @testrun[:exit_code], # might be nil, e.g., when the run did not finish
      status: @testrun[:status],
      output: @testrun[:output].presence, # TODO: Remove duplicated saving of the output after creating TestrunMessages
      container_execution_time: @testrun[:container_execution_time],
      waiting_for_container_time: @testrun[:waiting_for_container_time]
    )
    TestrunMessage.create_for(testrun, @testrun[:messages])
    TestrunExecutionEnvironment.create(testrun: testrun, execution_environment: @submission.used_execution_environment)
  end

  def send_hints(tubesock, errors)
    return if @embed_options[:disable_hints]

    errors = errors.to_a.uniq(&:hint)
    errors.each do |error|
      send_and_store tubesock, {cmd: :hint, hint: error.hint, description: error.error_template.description}
    end
  end

  def set_files_and_specific_file
    # @files contains all visible files for the user
    # @file contains the specific file requested for run / test / render / ...
    set_files
    @file = @files.detect {|file| file.filepath == sanitize_filename }
    head :not_found unless @file
  end

  def set_files
    @files = @submission.collect_files.select(&:visible)
  end

  def set_mime_type
    @mime_type = Mime::Type.lookup_by_extension(@file.file_type.file_extension.gsub(/^\./, ''))
    response.headers['Content-Type'] = @mime_type.to_s
  end

  def set_submission
    @submission = Submission.find(params[:id])
    authorize!
  end

  def set_testrun
    @testrun = {
      messages: [],
      exit_code: nil,
      status: nil,
    }
  end

  def retrieve_message_from_output(data, stream)
    parsed = JSON.parse(data)
    if parsed.instance_of?(Hash) && parsed.key?('cmd')
      parsed.symbolize_keys!
      # Symbolize two values if present
      parsed[:cmd] = parsed[:cmd].to_sym
      parsed[:stream] = parsed[:stream].to_sym if parsed.key? :stream
      parsed
    else
      {cmd: :write, stream: stream, data: data}
    end
  rescue JSON::ParserError
    {cmd: :write, stream: stream, data: data}
  end
end
