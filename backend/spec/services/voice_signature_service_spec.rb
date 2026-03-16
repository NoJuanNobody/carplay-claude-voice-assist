# frozen_string_literal: true

require "rails_helper"

RSpec.describe VoiceSignatureService do
  let(:service) { described_class.new }
  let(:user) { create(:user) }

  def generate_embeddings(size: 128, seed: nil)
    rng = seed ? Random.new(seed) : Random.new
    Array.new(size) { rng.rand(-1.0..1.0) }
  end

  def normalized(embeddings)
    magnitude = Math.sqrt(embeddings.sum { |e| e**2 })
    embeddings.map { |e| (e / magnitude).round(8) }
  end

  describe "#enroll" do
    let(:signature_data) { { embeddings: generate_embeddings, samples: %w[s1 s2 s3] } }

    it "stores normalized embeddings on the user" do
      result = service.enroll(user, signature_data)

      expect(result[:enrolled]).to be true
      expect(result[:embedding_size]).to eq(128)

      user.reload
      stored = user.voice_signature_data
      expect(stored["embeddings"].length).to eq(128)
      expect(stored["embedding_version"]).to eq("v1")
      expect(stored["sample_count"]).to eq(3)
    end

    it "normalizes embeddings to unit length" do
      service.enroll(user, signature_data)

      user.reload
      embeddings = user.voice_signature_data["embeddings"]
      magnitude = Math.sqrt(embeddings.sum { |e| e**2 })
      expect(magnitude).to be_within(0.001).of(1.0)
    end

    context "with missing embeddings" do
      it "raises EnrollmentError" do
        expect { service.enroll(user, {}) }
          .to raise_error(VoiceSignatureService::EnrollmentError, /Missing embeddings/)
      end
    end

    context "with embeddings too short" do
      it "raises EnrollmentError" do
        expect { service.enroll(user, { embeddings: [1.0, 2.0] }) }
          .to raise_error(VoiceSignatureService::EnrollmentError, /too short/)
      end
    end

    context "with embeddings too long" do
      it "raises EnrollmentError" do
        expect { service.enroll(user, { embeddings: Array.new(3000) { 1.0 } }) }
          .to raise_error(VoiceSignatureService::EnrollmentError, /too long/)
      end
    end

    context "with non-numeric embeddings" do
      it "raises EnrollmentError" do
        expect { service.enroll(user, { embeddings: Array.new(128) { "not_a_number" } }) }
          .to raise_error(VoiceSignatureService::EnrollmentError, /array of numbers/)
      end
    end
  end

  describe "#verify" do
    let(:original_embeddings) { generate_embeddings(seed: 42) }

    before do
      service.enroll(user, { embeddings: original_embeddings })
    end

    it "verifies the same voice with high confidence" do
      result = service.verify(user, { embeddings: original_embeddings })

      expect(result[:verified]).to be true
      expect(result[:confidence]).to be >= 0.85
    end

    it "rejects a different voice" do
      different_embeddings = generate_embeddings(seed: 99)
      result = service.verify(user, { embeddings: different_embeddings })

      expect(result[:verified]).to be false
      expect(result[:confidence]).to be < 0.85
    end

    it "raises VerificationError when no signature is enrolled" do
      user_without_sig = create(:user)
      expect { service.verify(user_without_sig, { embeddings: original_embeddings }) }
        .to raise_error(VoiceSignatureService::VerificationError, /No voice signature enrolled/)
    end

    it "raises VerificationError on dimension mismatch" do
      short_embeddings = generate_embeddings(size: 64)
      expect { service.verify(user, { embeddings: short_embeddings }) }
        .to raise_error(VoiceSignatureService::VerificationError, /dimension mismatch/)
    end
  end

  describe "#delete_signature" do
    it "removes the voice signature from user" do
      service.enroll(user, { embeddings: generate_embeddings })
      result = service.delete_signature(user)

      expect(result[:deleted]).to be true
      user.reload
      expect(user.voice_signature_data).to be_nil
    end

    it "raises SignatureError when no signature exists" do
      expect { service.delete_signature(user) }
        .to raise_error(VoiceSignatureService::SignatureError, /No voice signature enrolled/)
    end
  end
end
