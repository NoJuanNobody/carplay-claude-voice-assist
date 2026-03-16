# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::MessagesAdapter do
  let(:adapter) { described_class.new }
  let(:user) { create(:user) }

  describe "#execute" do
    context "sending a message" do
      it "sends a message successfully" do
        result = adapter.execute(
          { "contact" => "Mom", "message" => "On my way!", "action" => "send_message" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:contact]).to eq("Mom")
        expect(result.data[:message]).to eq("On my way!")
        expect(result.data[:sent]).to be true
        expect(result.data[:message_id]).to be_present
        expect(result.data[:sent_at]).to be_present
      end

      it "infers send_message action when message field is present" do
        result = adapter.execute(
          { "contact" => "Alex", "message" => "Hey there" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:sent]).to be true
      end

      it "uses specified service" do
        result = adapter.execute(
          { "contact" => "Mom", "message" => "Hi!", "service" => "imessage", "action" => "send_message" },
          user: user
        )

        expect(result.data[:service]).to eq("imessage")
      end

      it "defaults to sms service" do
        result = adapter.execute(
          { "contact" => "Mom", "message" => "Hi!", "action" => "send_message" },
          user: user
        )

        expect(result.data[:service]).to eq("sms")
      end

      it "raises ValidationError when contact is missing" do
        expect {
          adapter.execute({ "message" => "Hi!", "action" => "send_message" }, user: user)
        }.to raise_error(Integrations::BaseAdapter::ValidationError, /contact/)
      end

      it "raises ValidationError when message text is missing" do
        expect {
          adapter.execute({ "contact" => "Mom", "action" => "send_message" }, user: user)
        }.to raise_error(Integrations::BaseAdapter::ValidationError, /message/)
      end
    end

    context "reading messages" do
      it "reads messages successfully" do
        result = adapter.execute(
          { "action" => "read_messages" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:messages]).to be_an(Array)
        expect(result.data[:message_count]).to be_a(Integer)
      end

      it "filters by contact" do
        result = adapter.execute(
          { "contact" => "Mom", "action" => "read_messages" },
          user: user
        )

        expect(result.success).to be true
        result.data[:messages].each do |msg|
          expect(msg[:from].downcase).to eq("mom")
        end
      end

      it "filters by unread status" do
        result = adapter.execute(
          { "unread_only" => true, "action" => "read_messages" },
          user: user
        )

        expect(result.success).to be true
        result.data[:messages].each do |msg|
          expect(msg[:unread]).to be true
        end
      end

      it "respects limit parameter" do
        result = adapter.execute(
          { "unread_only" => false, "limit" => 2, "action" => "read_messages" },
          user: user
        )

        expect(result.data[:messages].length).to be <= 2
      end

      it "infers read_messages when no message field present" do
        result = adapter.execute({}, user: user)

        expect(result.success).to be true
        expect(result.data[:messages]).to be_an(Array)
      end
    end
  end
end
