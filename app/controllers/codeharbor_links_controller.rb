# frozen_string_literal: true

class CodeharborLinksController < ApplicationController
  include CommonBehavior
  before_action :set_codeharbor_link, only: %i[show edit update destroy]

  def new
    @codeharbor_link = CodeharborLink.new
    authorize!
  end

  def edit
    authorize!
  end

  def create
    @codeharbor_link = CodeharborLink.new(codeharbor_link_params)
    @codeharbor_link.user = current_user
    authorize!
    create_and_respond(object: @codeharbor_link, path: proc { @codeharbor_link.user })
  end

  def update
    authorize!
    update_and_respond(object: @codeharbor_link, params: codeharbor_link_params, path: @codeharbor_link.user)
  end

  def destroy
    destroy_and_respond(object: @codeharbor_link, path: @codeharbor_link.user)
  end

  private

  def authorize!
    authorize @codeharbor_link
  end

  def set_codeharbor_link
    @codeharbor_link = CodeharborLink.find(params[:id])
    @codeharbor_link.user = current_user
    authorize!
  end

  def codeharbor_link_params
    params.require(:codeharbor_link).permit(:push_url, :oauth2token, :client_id, :client_secret)
  end
end
