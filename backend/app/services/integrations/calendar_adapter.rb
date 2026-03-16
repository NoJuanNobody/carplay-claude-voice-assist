# frozen_string_literal: true

module Integrations
  class CalendarAdapter < BaseAdapter
    DEFAULT_TIMEOUT = 10

    SUPPORTED_ACTIONS = %w[get_calendar_events set_reminder].freeze

    def execute(input, user:)
      with_timeout do
        action = fetch_input(input, :action) || infer_action(input)

        case action
        when "get_calendar_events"
          get_calendar_events(input, user: user)
        when "set_reminder"
          set_reminder(input, user: user)
        else
          error_result("Unknown calendar action: #{action}")
        end
      end
    end

    private

    def infer_action(input)
      return "set_reminder" if fetch_input(input, :text).present?

      "get_calendar_events"
    end

    def get_calendar_events(input, user:)
      date = fetch_input(input, :date, Date.current.iso8601)
      limit = fetch_input(input, :limit, 5).to_i
      calendar_name = fetch_input(input, :calendar_name)

      log_execution(:get_calendar_events, date: date, limit: limit, user_id: user.id)

      # Simulates EventKit integration
      # In production, this would query the iOS companion app's EventKit data
      events = simulate_calendar_events(date, limit: limit, calendar_name: calendar_name)

      success_result(
        date: date,
        calendar_name: calendar_name || "All Calendars",
        events: events,
        event_count: events.length
      )
    end

    def set_reminder(input, user:)
      validate_required!(input, :text)

      text = fetch_input(input, :text)
      time = fetch_input(input, :time)
      location = fetch_input(input, :location)

      log_execution(:set_reminder, text: text.truncate(50), user_id: user.id)

      # Simulates EventKit Reminders integration
      reminder_time = parse_reminder_time(time)

      success_result(
        reminder_id: SecureRandom.uuid,
        text: text,
        scheduled_at: reminder_time&.iso8601,
        location_trigger: location,
        created: true
      )
    end

    def simulate_calendar_events(date, limit:, calendar_name:)
      parsed_date = Date.parse(date) rescue Date.current
      base_hour = 9

      events = [
        { title: "Team Standup", start_time: "#{parsed_date}T09:00:00", end_time: "#{parsed_date}T09:30:00", calendar: "Work", location: "Zoom" },
        { title: "Lunch with Alex", start_time: "#{parsed_date}T12:00:00", end_time: "#{parsed_date}T13:00:00", calendar: "Personal", location: "Downtown Cafe" },
        { title: "Project Review", start_time: "#{parsed_date}T14:00:00", end_time: "#{parsed_date}T15:00:00", calendar: "Work", location: "Conference Room B" },
        { title: "Dentist Appointment", start_time: "#{parsed_date}T16:30:00", end_time: "#{parsed_date}T17:30:00", calendar: "Personal", location: "123 Health St" },
        { title: "Gym", start_time: "#{parsed_date}T18:00:00", end_time: "#{parsed_date}T19:00:00", calendar: "Personal", location: "FitLife Gym" }
      ]

      events = events.select { |e| e[:calendar] == calendar_name } if calendar_name.present?
      events.first(limit)
    end

    def parse_reminder_time(time_str)
      return nil if time_str.blank?

      if time_str.match?(/\Ain\s+(\d+)\s+(minute|hour|day)/i)
        match = time_str.match(/in\s+(\d+)\s+(minute|hour|day)s?/i)
        amount = match[1].to_i
        unit = match[2].downcase

        case unit
        when "minute" then Time.current + amount.minutes
        when "hour" then Time.current + amount.hours
        when "day" then Time.current + amount.days
        end
      else
        Time.parse(time_str) rescue Time.current + 1.hour
      end
    end
  end
end
