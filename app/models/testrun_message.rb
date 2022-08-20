# frozen_string_literal: true

class TestrunMessage < ApplicationRecord
  belongs_to :testrun

  enum cmd: {
    input: 0,
    write: 1,
    clear: 2,
    turtle: 3,
    turtlebatch: 4,
    render: 5,
    exit: 6,
    status: 7,
    hint: 8,
    client_kill: 9,
    exception: 10,
    result: 11,
    canvasevent: 12,
    timeout: 13, # TODO: Shouldn't be in the data, this is a status and can be removed after the migration finished
    out_of_memory: 14, # TODO: Shouldn't be in the data, this is a status and can be removed after the migration finished
  }, _default: :write, _prefix: true

  enum stream: {
    stdin: 0,
    stdout: 1,
    stderr: 2,
  }, _prefix: true

  validates :cmd, presence: true
  validates :timestamp, presence: true
  validates :stream, length: {minimum: 0, allow_nil: false}, if: -> { cmd_write? }
  validates :log, length: {minimum: 0, allow_nil: false}, if: -> { cmd_write? }
  validate :either_data_or_log

  default_scope { order(timestamp: :asc) }
  scope :output, -> { where(cmd: 1, stream: %i[stdout stderr]) }

  def self.create_for(testrun, messages)
    # We don't want to store anything if the testrun passed
    return if testrun.passed?

    messages.map! do |message|
      # We create a new hash and move all known keys
      result = {}
      result[:testrun] = testrun
      result[:log] = (message.delete(:log) || message.delete(:data)) if message[:cmd] == :write || message.key?(:log)
      result[:timestamp] = message.delete :timestamp
      result[:stream] = message.delete :stream if message.key?(:stream)
      result[:cmd] = message.delete :cmd
      # The remaining keys will be stored in the `data` column
      result[:data] = message.presence if message.present?
      result
    end

    # Before storing all messages, we truncate some to save storage
    filtered_messages = filter_messages_by_size testrun, messages

    # An array with hashes is passed, all are stored
    TestrunMessage.create!(filtered_messages)
  end

  def self.filter_messages_by_size(testrun, messages)
    limits = if testrun.submission.cause == 'requestComments'
               {data: {limit: 25, size: 0}, log: {limit: 5000, size: 0}}
             else
               {data: {limit: 10, size: 0}, log: {limit: 500, size: 0}}
             end

    filtered_messages = messages.map do |message|
      if message.key?(:log) && limits[:log][:size] < limits[:log][:limit]
        message[:log] = message[:log][0, limits[:log][:limit] - limits[:log][:size]]
        limits[:log][:size] += message[:log].size
      elsif message[:data] && limits[:data][:size] < limits[:data][:limit]
        limits[:data][:size] += 1
      elsif !message.key?(:log) && limits[:data][:size] < limits[:data][:limit]
        # Accept short TestrunMessages (e.g. just transporting a status information)
        # without increasing the `limits[:data][:limit]` before the limit is reached
      else
        # Clear all remaining messages
        message = nil
      end
      message
    end
    filtered_messages.select(&:present?)
  end

  def either_data_or_log
    if [data, log].count(&:present?) > 1
      errors.add(log, "can't be present if data is also present")
    end
  end
  private :either_data_or_log
end
