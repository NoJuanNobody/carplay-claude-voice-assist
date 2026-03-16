# frozen_string_literal: true

module Api
  module V1
    class SessionsController < ApplicationController
      before_action :set_session, only: %i[destroy create_message messages]

      # POST /api/v1/sessions
      def create
        context = ContextManager.new(user: current_user)
        result = context.start_session(vehicle_id: params[:vehicle_id])

        render json: { session: result }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Vehicle not found" }, status: :not_found
      end

      # DELETE /api/v1/sessions/:id
      def destroy
        context = ContextManager.new(user: current_user, session: @voice_session)
        result = context.end_session

        render json: { session: result }, status: :ok
      rescue ContextManager::SessionError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/sessions/:id/messages
      def create_message
        text = params.require(:text)
        driving_state = params.fetch(:driving_state, "unknown")

        context = ContextManager.new(user: current_user, session: @voice_session)
        result = context.process_message(text, driving_state: driving_state)

        render json: { message: result }, status: :created
      rescue ContextManager::SessionError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ClaudeClient::ApiError => e
        render json: { error: "Assistant unavailable: #{e.message}" }, status: :service_unavailable
      end

      # GET /api/v1/sessions/:id/messages
      def messages
        messages = @voice_session.conversation_messages
          .order(created_at: :asc)
          .select(:id, :role, :content, :tool_calls, :token_count, :latency_ms, :created_at)

        render json: {
          messages: messages.map { |m| message_response(m) },
          count: messages.size
        }, status: :ok
      end

      private

      def set_session
        @voice_session = current_user.voice_sessions.find(params[:id] || params[:session_id])
      end

      def message_response(message)
        {
          id: message.id,
          role: message.role,
          content: message.content,
          tool_calls: message.tool_calls,
          token_count: message.token_count,
          latency_ms: message.latency_ms,
          created_at: message.created_at.iso8601
        }
      end
    end
  end
end
