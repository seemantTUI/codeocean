# frozen_string_literal: true

require 'rails_helper'

describe ExecutionEnvironmentsController do
  let(:execution_environment) { FactoryBot.create(:ruby) }
  let(:user) { FactoryBot.create(:admin) }

  before do
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:sync_to_runner_management).and_return(nil)
  end

  describe 'POST #create' do
    before { allow(DockerClient).to receive(:image_tags).at_least(:once).and_return([]) }

    context 'with a valid execution environment' do
      let(:perform_request) { proc { post :create, params: {execution_environment: FactoryBot.build(:ruby).attributes} } }

      before { perform_request.call }

      expect_assigns(docker_images: Array)
      expect_assigns(execution_environment: ExecutionEnvironment)

      it 'creates the execution environment' do
        expect { perform_request.call }.to change(ExecutionEnvironment, :count).by(1)
      end

      it 'registers the execution environment with the runner management' do
        expect(controller).to have_received(:sync_to_runner_management)
      end

      expect_redirect(ExecutionEnvironment.last)
    end

    context 'with an invalid execution environment' do
      before { post :create, params: {execution_environment: {}} }

      expect_assigns(execution_environment: ExecutionEnvironment)
      expect_status(200)
      expect_template(:new)

      it 'does not register the execution environment with the runner management' do
        expect(controller).not_to have_received(:sync_to_runner_management)
      end
    end
  end

  describe 'DELETE #destroy' do
    before { delete :destroy, params: {id: execution_environment.id} }

    expect_assigns(execution_environment: :execution_environment)

    it 'destroys the execution environment' do
      execution_environment = FactoryBot.create(:ruby)
      expect { delete :destroy, params: {id: execution_environment.id} }.to change(ExecutionEnvironment, :count).by(-1)
    end

    expect_redirect(:execution_environments)
  end

  describe 'GET #edit' do
    before do
      allow(DockerClient).to receive(:image_tags).at_least(:once).and_return([])
      get :edit, params: {id: execution_environment.id}
    end

    expect_assigns(docker_images: Array)
    expect_assigns(execution_environment: :execution_environment)
    expect_status(200)
    expect_template(:edit)
  end

  describe 'POST #execute_command' do
    let(:command) { 'which ruby' }

    before do
      runner = instance_double 'runner'
      allow(Runner).to receive(:for).with(user, execution_environment).and_return runner
      allow(runner).to receive(:execute_command).and_return({})
      post :execute_command, params: {command: command, id: execution_environment.id}
    end

    expect_assigns(execution_environment: :execution_environment)
    expect_json
    expect_status(200)
  end

  describe 'GET #index' do
    before do
      FactoryBot.create_pair(:ruby)
      get :index
    end

    expect_assigns(execution_environments: ExecutionEnvironment.all)
    expect_status(200)
    expect_template(:index)
  end

  describe 'GET #new' do
    before do
      allow(DockerClient).to receive(:image_tags).at_least(:once).and_return([])
      get :new
    end

    expect_assigns(docker_images: Array)
    expect_assigns(execution_environment: ExecutionEnvironment)
    expect_status(200)
    expect_template(:new)
  end

  describe '#set_docker_images' do
    context 'when Docker is available' do
      let(:docker_images) { [1, 2, 3] }

      before do
        allow(Runner).to receive(:strategy_class).and_return Runner::Strategy::DockerContainerPool
        allow(DockerClient).to receive(:check_availability!).at_least(:once)
        allow(DockerClient).to receive(:image_tags).and_return(docker_images)
        controller.send(:set_docker_images)
      end

      expect_assigns(docker_images: :docker_images)
    end

    context 'when Docker is unavailable' do
      let(:error_message) { 'Docker is unavailable' }

      before do
        allow(Runner).to receive(:strategy_class).and_return Runner::Strategy::DockerContainerPool
        allow(DockerClient).to receive(:check_availability!).at_least(:once).and_raise(DockerClient::Error.new(error_message))
        controller.send(:set_docker_images)
      end

      it 'fails gracefully' do
        expect { controller.send(:set_docker_images) }.not_to raise_error
      end

      expect_assigns(docker_images: Array)
      expect_flash_message(:warning, :error_message)
    end
  end

  describe 'GET #shell' do
    before { get :shell, params: {id: execution_environment.id} }

    expect_assigns(execution_environment: :execution_environment)
    expect_status(200)
    expect_template(:shell)
  end

  describe 'GET #statistics' do
    before { get :statistics, params: {id: execution_environment.id} }

    expect_assigns(execution_environment: :execution_environment)
    expect_status(200)
    expect_template(:statistics)
  end

  describe 'GET #show' do
    before { get :show, params: {id: execution_environment.id} }

    expect_assigns(execution_environment: :execution_environment)
    expect_status(200)
    expect_template(:show)
  end

  describe 'PUT #update' do
    context 'with a valid execution environment' do
      before do
        allow(DockerClient).to receive(:image_tags).at_least(:once).and_return([])
        allow(controller).to receive(:sync_to_runner_management).and_return(nil)
        put :update, params: {execution_environment: FactoryBot.attributes_for(:ruby), id: execution_environment.id}
      end

      expect_assigns(docker_images: Array)
      expect_assigns(execution_environment: ExecutionEnvironment)
      expect_redirect(:execution_environment)

      it 'updates the execution environment at the runner management' do
        expect(controller).to have_received(:sync_to_runner_management)
      end
    end

    context 'with an invalid execution environment' do
      before { put :update, params: {execution_environment: {name: ''}, id: execution_environment.id} }

      expect_assigns(execution_environment: ExecutionEnvironment)
      expect_status(200)
      expect_template(:edit)

      it 'does not update the execution environment at the runner management' do
        expect(controller).not_to have_received(:sync_to_runner_management)
      end
    end
  end

  describe '#sync_all_to_runner_management' do
    let(:execution_environments) { FactoryBot.build_list(:ruby, 3) }

    let(:codeocean_config) { instance_double(CodeOcean::Config) }
    let(:runner_management_config) { {runner_management: {enabled: true, strategy: :poseidon}} }

    before do
      # Ensure to reset the memorized helper
      Runner.instance_variable_set :@strategy_class, nil
      allow(CodeOcean::Config).to receive(:new).with(:code_ocean).and_return(codeocean_config)
      allow(codeocean_config).to receive(:read).and_return(runner_management_config)
    end

    it 'copies all execution environments to the runner management' do
      allow(ExecutionEnvironment).to receive(:all).and_return(execution_environments)

      execution_environments.each do |execution_environment|
        allow(Runner::Strategy::Poseidon).to receive(:sync_environment).with(execution_environment).and_return(true)
        expect(Runner::Strategy::Poseidon).to receive(:sync_environment).with(execution_environment).once
      end

      post :sync_all_to_runner_management
    end
  end
end
