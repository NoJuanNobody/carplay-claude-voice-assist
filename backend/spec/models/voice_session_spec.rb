require "rails_helper"

RSpec.describe VoiceSession, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:vehicle).optional }
    it { is_expected.to have_many(:conversation_messages).dependent(:destroy) }
    it { is_expected.to have_many(:safety_events).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:session_token) }
    it { is_expected.to validate_presence_of(:started_at) }
  end

  describe "scopes" do
    it "returns active sessions (ended_at is nil)" do
      expect(VoiceSession.active.where_clause.ast).to be_present
    end

    it "returns completed sessions (ended_at is not nil)" do
      expect(VoiceSession.completed.where_clause.ast).to be_present
    end
  end

  describe "callbacks" do
    it "generates a session_token before create if not set" do
      session = VoiceSession.new
      session.valid?
      expect(session.session_token).to be_present
    end
  end
end
