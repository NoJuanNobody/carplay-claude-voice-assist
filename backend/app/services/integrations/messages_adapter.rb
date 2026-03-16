# frozen_string_literal: true

module Integrations
  class MessagesAdapter < BaseAdapter
    DEFAULT_TIMEOUT = 10

    SUPPORTED_ACTIONS = %w[send_message read_messages].freeze

    def execute(input, user:)
      with_timeout do
        action = fetch_input(input, :action) || infer_action(input)

        case action
        when "send_message"
          send_message(input, user: user)
        when "read_messages"
          read_messages(input, user: user)
        else
          error_result("Unknown messages action: #{action}")
        end
      end
    end

    private

    def infer_action(input)
      return "send_message" if fetch_input(input, :message).present?

      "read_messages"
    end

    def send_message(input, user:)
      validate_required!(input, :contact, :message)

      contact = fetch_input(input, :contact)
      message = fetch_input(input, :message)
      service = fetch_input(input, :service, "sms")

      log_execution(:send_message, contact: contact, service: service, user_id: user.id)

      # Simulates Messages framework integration
      # In production, this would trigger the iOS companion app to send via MessageUI
      success_result(
        message_id: SecureRandom.uuid,
        contact: contact,
        message: message,
        service: service,
        sent: true,
        sent_at: Time.current.iso8601
      )
    end

    def read_messages(input, user:)
      contact = fetch_input(input, :contact)
      unread_only = fetch_input(input, :unread_only, true)
      limit = fetch_input(input, :limit, 5).to_i

      log_execution(:read_messages, contact: contact, unread_only: unread_only, user_id: user.id)

      # Simulates reading messages from the iOS Messages database
      messages = simulate_messages(contact: contact, unread_only: unread_only, limit: limit)

      success_result(
        contact: contact || "All Contacts",
        unread_only: unread_only,
        messages: messages,
        message_count: messages.length
      )
    end

    def simulate_messages(contact:, unread_only:, limit:)
      all_messages = [
        { from: "Mom", text: "Don't forget dinner tonight at 7!", time: 30.minutes.ago.iso8601, unread: true },
        { from: "Alex", text: "Running 10 min late", time: 1.hour.ago.iso8601, unread: true },
        { from: "Boss", text: "Great presentation today!", time: 2.hours.ago.iso8601, unread: false },
        { from: "Mom", text: "Can you pick up milk?", time: 3.hours.ago.iso8601, unread: false },
        { from: "Alex", text: "See you at the coffee shop", time: 1.day.ago.iso8601, unread: false }
      ]

      filtered = all_messages
      filtered = filtered.select { |m| m[:from].downcase == contact.downcase } if contact.present?
      filtered = filtered.select { |m| m[:unread] } if unread_only
      filtered.first(limit)
    end
  end
end
