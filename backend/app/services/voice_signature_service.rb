# frozen_string_literal: true

class VoiceSignatureService
  class SignatureError < StandardError; end
  class EnrollmentError < SignatureError; end
  class VerificationError < SignatureError; end

  SIMILARITY_THRESHOLD = 0.85
  MIN_EMBEDDING_SIZE = 64
  MAX_EMBEDDING_SIZE = 2048

  # Enrolls a voice signature for the given user.
  # signature_data should contain an "embeddings" array of floats.
  def enroll(user, signature_data)
    embeddings = extract_embeddings(signature_data)
    validate_embeddings!(embeddings)

    normalized = normalize_embeddings(embeddings)

    voice_data = {
      "embeddings" => normalized,
      "enrolled_at" => Time.current.iso8601,
      "embedding_version" => "v1",
      "sample_count" => Array(signature_data[:samples] || signature_data["samples"]).length.clamp(1, 100)
    }

    user.update!(voice_signature_data: voice_data)

    {
      enrolled: true,
      enrolled_at: voice_data["enrolled_at"],
      embedding_size: normalized.length
    }
  rescue ActiveRecord::RecordInvalid => e
    raise EnrollmentError, "Failed to save voice signature: #{e.message}"
  end

  # Verifies a voice signature against the enrolled signature.
  # Returns { verified: bool, confidence: float }.
  def verify(user, signature_data)
    stored = user.voice_signature_data
    raise VerificationError, "No voice signature enrolled for this user" if stored.blank?

    incoming_embeddings = extract_embeddings(signature_data)
    validate_embeddings!(incoming_embeddings)

    stored_embeddings = stored["embeddings"]
    incoming_normalized = normalize_embeddings(incoming_embeddings)

    if stored_embeddings.length != incoming_normalized.length
      raise VerificationError,
            "Embedding dimension mismatch: expected #{stored_embeddings.length}, got #{incoming_normalized.length}"
    end

    similarity = cosine_similarity(stored_embeddings, incoming_normalized)

    {
      verified: similarity >= SIMILARITY_THRESHOLD,
      confidence: similarity.round(4)
    }
  end

  # Removes the voice signature from the user record.
  def delete_signature(user)
    raise SignatureError, "No voice signature enrolled for this user" if user.voice_signature_data.blank?

    user.update!(voice_signature_data: nil)
    { deleted: true }
  end

  private

  def extract_embeddings(signature_data)
    data = signature_data.is_a?(Hash) ? signature_data : {}
    embeddings = data[:embeddings] || data["embeddings"]
    raise EnrollmentError, "Missing embeddings in signature data" if embeddings.blank?

    embeddings
  end

  def validate_embeddings!(embeddings)
    unless embeddings.is_a?(Array) && embeddings.all? { |e| e.is_a?(Numeric) }
      raise EnrollmentError, "Embeddings must be an array of numbers"
    end

    if embeddings.length < MIN_EMBEDDING_SIZE
      raise EnrollmentError, "Embeddings too short: minimum #{MIN_EMBEDDING_SIZE} dimensions required"
    end

    if embeddings.length > MAX_EMBEDDING_SIZE
      raise EnrollmentError, "Embeddings too long: maximum #{MAX_EMBEDDING_SIZE} dimensions allowed"
    end
  end

  def normalize_embeddings(embeddings)
    magnitude = Math.sqrt(embeddings.sum { |e| e**2 })
    return embeddings.map { 0.0 } if magnitude.zero?

    embeddings.map { |e| (e / magnitude).round(8) }
  end

  def cosine_similarity(vec_a, vec_b)
    dot_product = vec_a.zip(vec_b).sum { |a, b| a * b }
    magnitude_a = Math.sqrt(vec_a.sum { |a| a**2 })
    magnitude_b = Math.sqrt(vec_b.sum { |b| b**2 })

    return 0.0 if magnitude_a.zero? || magnitude_b.zero?

    (dot_product / (magnitude_a * magnitude_b)).clamp(-1.0, 1.0)
  end
end
