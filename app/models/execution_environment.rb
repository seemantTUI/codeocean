# frozen_string_literal: true

require File.expand_path('../../lib/active_model/validations/boolean_presence_validator', __dir__)

class ExecutionEnvironment < ApplicationRecord
  include Creation
  include DefaultValues

  VALIDATION_COMMAND = 'whoami'
  DEFAULT_CPU_LIMIT = 20
  DEFAULT_MEMORY_LIMIT = 256
  MINIMUM_MEMORY_LIMIT = 4

  after_initialize :set_default_values

  has_many :exercises
  belongs_to :file_type
  has_many :error_templates

  scope :with_exercises, -> { where('id IN (SELECT execution_environment_id FROM exercises)') }

  validate :valid_test_setup?
  validate :working_docker_image?, if: :validate_docker_image?
  validates :docker_image, presence: true
  validates :memory_limit,
    numericality: {greater_than_or_equal_to: MINIMUM_MEMORY_LIMIT, only_integer: true}, presence: true
  validates :network_enabled, boolean_presence: true
  validates :name, presence: true
  validates :permitted_execution_time, numericality: {only_integer: true}, presence: true
  validates :pool_size, numericality: {only_integer: true}, presence: true
  validates :run_command, presence: true
  validates :cpu_limit, presence: true, numericality: {greater_than: 0, only_integer: true}
  before_validation :clean_exposed_ports
  validates :exposed_ports, array: {numericality: {greater_than_or_equal_to: 0, less_than: 65_536, only_integer: true}}

  def set_default_values
    set_default_values_if_present(permitted_execution_time: 60, pool_size: 0)
  end
  private :set_default_values

  def to_s
    name
  end

  def to_json(*_args)
    {
      id: id,
      image: docker_image,
      prewarmingPoolSize: pool_size,
      cpuLimit: cpu_limit,
      memoryLimit: memory_limit,
      networkAccess: network_enabled,
      exposedPorts: exposed_ports,
    }.to_json
  end

  def exposed_ports_list
    exposed_ports.join(', ')
  end

  def clean_exposed_ports
    self.exposed_ports = exposed_ports.uniq.sort
  end
  private :clean_exposed_ports

  def valid_test_setup?
    if test_command? ^ testing_framework?
      errors.add(:test_command,
        I18n.t('activerecord.errors.messages.together',
          attribute: I18n.t('activerecord.attributes.execution_environment.testing_framework')))
    end
  end
  private :valid_test_setup?

  def validate_docker_image?
    docker_image.present? && !Rails.env.test?
  end
  private :validate_docker_image?

  def working_docker_image?
    runner = Runner.for(author, self)
    output = runner.execute_command(VALIDATION_COMMAND)
    errors.add(:docker_image, "error: #{output[:stderr]}") if output[:stderr].present?
  rescue Runner::Error => e
    errors.add(:docker_image, "error: #{e}")
  end
  private :working_docker_image?
end
