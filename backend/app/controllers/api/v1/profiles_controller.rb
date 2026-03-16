# frozen_string_literal: true

module Api
  module V1
    class ProfilesController < ApplicationController
      before_action :set_profile_service

      # GET /api/v1/profile
      def show
        profile = @profile_service.get_profile(current_user)
        render json: { profile: profile }, status: :ok
      end

      # PUT /api/v1/profile
      def update
        profile = @profile_service.update_profile(current_user, profile_params)
        render json: { profile: profile }, status: :ok
      rescue ProfileService::ValidationError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/profile/voice_signature
      def enroll_voice_signature
        signature_service = VoiceSignatureService.new
        result = signature_service.enroll(current_user, voice_signature_params)
        render json: { voice_signature: result }, status: :created
      rescue VoiceSignatureService::EnrollmentError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # DELETE /api/v1/profile/voice_signature
      def delete_voice_signature
        signature_service = VoiceSignatureService.new
        result = signature_service.delete_signature(current_user)
        render json: { voice_signature: result }, status: :ok
      rescue VoiceSignatureService::SignatureError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_profile_service
        @profile_service = ProfileService.new
      end

      def profile_params
        params.permit(
          :first_name, :last_name, :voice_speed, :voice_name,
          :language, :response_verbosity, :safety_level,
          custom_settings: {}
        ).to_h.symbolize_keys
      end

      def voice_signature_params
        params.permit(:samples, embeddings: []).to_h.symbolize_keys
      end
    end
  end
end
