# frozen_string_literal: true

class ProfileService
  class ProfileError < StandardError; end
  class ValidationError < ProfileError; end

  def initialize(cache_service: nil)
    @cache = cache_service || CacheService.new(namespace: "profiles")
  end

  # Creates a full user profile including preferences.
  # Returns the user with loaded preference association.
  def create_profile(user, params)
    preference_params = extract_preference_params(params)

    ActiveRecord::Base.transaction do
      user.update!(
        first_name: params[:first_name],
        last_name: params[:last_name]
      )

      preference = user.build_user_preference(preference_params)
      preference.save!
    end

    invalidate_cache(user)
    get_profile(user)
  rescue ActiveRecord::RecordInvalid => e
    raise ValidationError, e.message
  end

  # Updates an existing profile. Accepts user-level and preference-level params.
  def update_profile(user, params)
    user_params = params.slice(:first_name, :last_name)
    preference_params = extract_preference_params(params)

    ActiveRecord::Base.transaction do
      user.update!(user_params) if user_params.present?

      if preference_params.present?
        preference = user.user_preference || user.build_user_preference
        preference.update!(preference_params)
      end
    end

    invalidate_cache(user)
    get_profile(user)
  rescue ActiveRecord::RecordInvalid => e
    raise ValidationError, e.message
  end

  # Returns the full profile payload, reading from cache when available.
  def get_profile(user)
    cached = @cache.get_profile(user.id)
    return cached if cached

    profile_data = build_profile_data(user)
    @cache.set_profile(user.id, profile_data)
    profile_data
  end

  # Soft-deletes the user profile by clearing personal data and preferences.
  def delete_profile(user)
    ActiveRecord::Base.transaction do
      user.user_preference&.destroy!
      user.update!(
        first_name: nil,
        last_name: nil,
        voice_signature_data: nil
      )
    end

    invalidate_cache(user)
    true
  end

  private

  PREFERENCE_KEYS = %i[
    voice_speed voice_name language response_verbosity
    safety_level custom_settings
  ].freeze

  def extract_preference_params(params)
    params.slice(*PREFERENCE_KEYS)
  end

  def build_profile_data(user)
    user.reload
    preference = user.user_preference

    {
      "id" => user.id,
      "email" => user.email,
      "first_name" => user.first_name,
      "last_name" => user.last_name,
      "has_voice_signature" => user.voice_signature_data.present?,
      "created_at" => user.created_at.iso8601,
      "updated_at" => user.updated_at.iso8601,
      "preferences" => preference ? {
        "voice_speed" => preference.voice_speed,
        "voice_name" => preference.voice_name,
        "language" => preference.language,
        "response_verbosity" => preference.response_verbosity,
        "safety_level" => preference.safety_level,
        "custom_settings" => preference.custom_settings
      } : nil
    }
  end

  def invalidate_cache(user)
    @cache.delete("profile:#{user.id}")
  end
end
