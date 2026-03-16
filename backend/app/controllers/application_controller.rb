# frozen_string_literal: true

class ApplicationController < ActionController::API
  before_action :authenticate_user!

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity_error
  rescue_from ActionController::ParameterMissing, with: :bad_request

  private

  def authenticate_user!
    token = extract_token_from_header
    return render_unauthorized("Missing authorization token") unless token

    begin
      payload = decode_jwt(token)
      @current_user = User.find_by(id: payload["sub"], jti: payload["jti"])
      render_unauthorized("Invalid token") unless @current_user
    rescue JWT::DecodeError, JWT::ExpiredSignature => e
      render_unauthorized("Invalid token: #{e.message}")
    end
  end

  def current_user
    @current_user
  end

  def skip_authentication!
    true
  end

  def extract_token_from_header
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.split(" ").last
  end

  def decode_jwt(token)
    secret = Rails.application.credentials.devise_jwt_secret_key ||
             ENV.fetch("DEVISE_JWT_SECRET_KEY", "test-secret-key")
    JWT.decode(token, secret, true, algorithm: "HS256").first
  end

  def encode_jwt(user)
    secret = Rails.application.credentials.devise_jwt_secret_key ||
             ENV.fetch("DEVISE_JWT_SECRET_KEY", "test-secret-key")
    payload = {
      sub: user.id,
      jti: user.jti,
      iat: Time.current.to_i,
      exp: 24.hours.from_now.to_i
    }
    JWT.encode(payload, secret, "HS256")
  end

  def render_unauthorized(message = "Unauthorized")
    render json: { error: message }, status: :unauthorized
  end

  def not_found
    render json: { error: "Resource not found" }, status: :not_found
  end

  def unprocessable_entity_error(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end
end
