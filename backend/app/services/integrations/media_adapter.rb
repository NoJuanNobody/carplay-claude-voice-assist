# frozen_string_literal: true

module Integrations
  class MediaAdapter < BaseAdapter
    DEFAULT_TIMEOUT = 10

    SUPPORTED_ACTIONS = %w[play_music].freeze
    VALID_PLAYBACK_ACTIONS = %w[play pause skip previous volume_up volume_down].freeze

    def execute(input, user:)
      with_timeout do
        validate_required!(input, :action)

        action = fetch_input(input, :action)
        unless VALID_PLAYBACK_ACTIONS.include?(action)
          return error_result("Invalid playback action '#{action}'. Valid actions: #{VALID_PLAYBACK_ACTIONS.join(', ')}")
        end

        query = fetch_input(input, :query)
        source = fetch_input(input, :source, "spotify")

        log_execution(:play_music, action: action, query: query, source: source, user_id: user.id)

        # Simulates Apple Music / MediaPlayer framework integration
        # In production, this would interface with MPMusicPlayerController on iOS
        case action
        when "play"
          play(query: query, source: source)
        when "pause"
          success_result(action: "pause", state: "paused")
        when "skip"
          success_result(action: "skip", state: "playing", track: "Next Track")
        when "previous"
          success_result(action: "previous", state: "playing", track: "Previous Track")
        when "volume_up"
          success_result(action: "volume_up", volume: 0.8)
        when "volume_down"
          success_result(action: "volume_down", volume: 0.4)
        end
      end
    end

    private

    def play(query:, source:)
      if query.present?
        track = simulate_music_search(query, source: source)

        if track
          success_result(
            action: "play",
            state: "playing",
            track: track[:name],
            artist: track[:artist],
            album: track[:album],
            source: source,
            duration_seconds: track[:duration]
          )
        else
          error_result("Could not find '#{query}' on #{source}.")
        end
      else
        success_result(action: "play", state: "playing", resumed: true)
      end
    end

    def simulate_music_search(query, source:)
      # Simulated music search results
      {
        name: query.titleize,
        artist: "Artist",
        album: "Album",
        duration: 210 + (query.length * 5)
      }
    end
  end
end
