# frozen_string_literal: true

module Offline
  class FallbackResponseService
    NAVIGATION_KEYWORDS = %w[
      navigate directions route map destination address
      drive driving turn highway exit ramp freeway
      where how\ far how\ long eta distance
    ].freeze

    WEATHER_KEYWORDS = %w[
      weather temperature forecast rain snow wind
      sunny cloudy storm humidity cold hot warm
      degrees celsius fahrenheit
    ].freeze

    MUSIC_KEYWORDS = %w[
      play song music track album artist
      playlist pause skip next previous volume
      radio station podcast listen
    ].freeze

    MESSAGES_KEYWORDS = %w[
      text message send call phone read
      email reply respond notification voicemail
      contact dial ring
    ].freeze

    EMERGENCY_KEYWORDS = %w[
      emergency help accident crash 911
      ambulance police fire hospital
      sos danger
    ].freeze

    NAVIGATION_RESPONSES = [
      "I'm currently offline, so I can't provide live navigation. Please check your Maps app directly for directions.",
      "Navigation services require an internet connection. Your device's built-in Maps app may have offline maps available.",
      "I can't look up directions right now due to limited connectivity. Try using a previously downloaded offline map.",
      "I'm unable to calculate routes without a network connection. If you've saved this destination before, check your Maps app.",
      "Live navigation isn't available offline. For safety, please pull over to check your route when you have connectivity.",
      "I can't access mapping services at the moment. Your car's built-in navigation system may still work without internet."
    ].freeze

    WEATHER_RESPONSES = [
      "I can't check the weather right now because I'm offline. Tune into a local radio station for current conditions.",
      "Weather information requires an internet connection. Try an AM/FM weather radio station for local updates.",
      "I'm unable to fetch weather data without connectivity. Check the sky and drive accordingly.",
      "Weather services aren't available offline. Your car's outside temperature gauge can give you the current reading.",
      "I can't access weather forecasts right now. Consider turning on local radio for weather alerts.",
      "Current weather data is unavailable without a connection. Drive cautiously and watch for changing conditions."
    ].freeze

    MUSIC_RESPONSES = [
      "I can't stream music right now due to limited connectivity. Try playing downloaded songs from your music library.",
      "Streaming services aren't available offline. Check your device for any previously downloaded playlists.",
      "I'm unable to access music streaming without internet. Your locally stored music should still be available.",
      "Music streaming requires a connection. Try switching to FM/AM radio or any offline playlists you've saved.",
      "I can't play streaming music right now. Any songs downloaded to your device should work without internet.",
      "Online music isn't available at the moment. Try using your device's offline music library or local radio."
    ].freeze

    MESSAGES_RESPONSES = [
      "I can't send or read messages right now because I'm offline. Your messages will sync when connectivity is restored.",
      "Messaging requires an internet connection. Your message will be queued and sent once you're back online.",
      "I'm unable to access your messages without connectivity. They'll be available once the connection is restored.",
      "Message services aren't available offline. If urgent, try making a direct phone call instead.",
      "I can't read or send messages right now. For urgent communication, try a phone call which may work on cellular.",
      "Messaging features require internet. Phone calls may still work on a weak cellular connection if needed."
    ].freeze

    GENERAL_RESPONSES = [
      "I'm currently offline and can't process that request. Basic features will resume once connectivity is restored.",
      "That request requires an internet connection which isn't available right now. Please try again later.",
      "I'm operating in offline mode with limited capabilities. I can help with basic time, math, and unit conversions.",
      "I can't fully process that without an internet connection. Try again when you have connectivity.",
      "My capabilities are limited while offline. I can still help with simple calculations and tell you the time.",
      "I'm unable to handle that request without a network connection. Core offline features like time and math still work."
    ].freeze

    EMERGENCY_RESPONSES = [
      "If this is an emergency, please call 911 directly. I'm offline and cannot contact emergency services for you.",
      "For emergencies, dial 911 immediately. My connection is down, but phone calls may still work on cellular.",
      "Please call 911 directly for emergency assistance. I cannot reach emergency services without an internet connection.",
      "Emergency services require you to call 911 directly. Even without data, emergency calls usually go through on cellular.",
      "If you need emergency help, call 911 now. Cellular emergency calls work even without a data connection.",
      "For immediate danger, call 911. Emergency calls are prioritized by cell networks even without an active data plan."
    ].freeze

    CATEGORY_MAP = {
      navigation: { keywords: NAVIGATION_KEYWORDS, responses: NAVIGATION_RESPONSES },
      weather:    { keywords: WEATHER_KEYWORDS, responses: WEATHER_RESPONSES },
      music:      { keywords: MUSIC_KEYWORDS, responses: MUSIC_RESPONSES },
      messages:   { keywords: MESSAGES_KEYWORDS, responses: MESSAGES_RESPONSES },
      emergency:  { keywords: EMERGENCY_KEYWORDS, responses: EMERGENCY_RESPONSES },
      general:    { keywords: [], responses: GENERAL_RESPONSES }
    }.freeze

    # Returns a fallback response based on the detected intent.
    #
    # @param intent [String, Symbol, nil] explicit intent category, or nil to detect from params
    # @param params [Hash] optional params; :text is used for intent detection if intent is nil
    # @return [Hash] { text:, source:, category:, detected_at: }
    def get_response(intent = nil, params = {})
      category = resolve_category(intent, params)
      responses = CATEGORY_MAP.dig(category, :responses) || GENERAL_RESPONSES

      {
        text: responses.sample,
        source: "offline_fallback",
        category: category,
        detected_at: Time.current.iso8601
      }
    end

    # Detects the intent category from free-form text.
    #
    # @param text [String] user input text
    # @return [Symbol] the detected category
    def detect_intent(text)
      return :general if text.nil? || text.strip.empty?

      normalized = text.downcase.strip

      # Emergency takes priority
      return :emergency if matches_category?(normalized, :emergency)

      %i[navigation weather music messages].each do |category|
        return category if matches_category?(normalized, category)
      end

      :general
    end

    # Returns all available categories.
    #
    # @return [Array<Symbol>]
    def categories
      CATEGORY_MAP.keys
    end

    # Returns the number of fallback responses for a given category.
    #
    # @param category [Symbol]
    # @return [Integer]
    def response_count(category)
      CATEGORY_MAP.dig(category.to_sym, :responses)&.length || 0
    end

    private

    def resolve_category(intent, params)
      if intent
        category = intent.to_sym
        return category if CATEGORY_MAP.key?(category)
      end

      text = params[:text] || params["text"]
      detect_intent(text)
    end

    def matches_category?(text, category)
      keywords = CATEGORY_MAP.dig(category, :keywords) || []
      keywords.any? { |kw| text.include?(kw) }
    end
  end
end
