# frozen_string_literal: true

module Api
  module V1
    class AuthController < ApplicationController
      skip_before_action :authenticate_user!, only: %i[register login]

      # POST /api/v1/auth/register
      def register
        user = User.new(register_params)

        ActiveRecord::Base.transaction do
          user.save!

          profile_service = ProfileService.new
          profile_params = params.permit(
            :first_name, :last_name, :voice_speed, :voice_name,
            :language, :response_verbosity, :safety_level
          ).to_h.symbolize_keys

          profile_service.create_profile(user, profile_params)
        end

        token = encode_jwt(user)

        render json: {
          token: token,
          user: user_response(user)
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ProfileService::ValidationError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/auth/login
      def login
        user = User.find_by(email: login_params[:email])

        if user&.valid_password?(login_params[:password])
          user.update!(jti: SecureRandom.uuid)
          token = encode_jwt(user)

          render json: {
            token: token,
            user: user_response(user)
          }, status: :ok
        else
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

      # DELETE /api/v1/auth/logout
      def logout
        current_user.update!(jti: SecureRandom.uuid)
        render json: { message: "Logged out successfully" }, status: :ok
      end

      # GET /api/v1/auth/me
      def me
        profile_service = ProfileService.new
        profile = profile_service.get_profile(current_user)

        render json: { user: profile }, status: :ok
      end

      private

      def register_params
        params.permit(:email, :password, :password_confirmation)
      end

      def login_params
        params.permit(:email, :password)
      end

      def user_response(user)
        {
          id: user.id,
          email: user.email,
          first_name: user.first_name,
          last_name: user.last_name,
          created_at: user.created_at.iso8601
        }
      end
    end
  end
end
