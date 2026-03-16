# Integration Architecture

## System Architecture

```
+------------------+       +-------------------+       +------------------+
|                  |       |                   |       |                  |
|  iOS CarPlay App | <---> |  Rails Backend    | <---> |  Claude API      |
|  (Swift/UIKit)   |  WS   |  (API + Services) |  HTTP |  (Anthropic)     |
|                  |       |                   |       |                  |
+------------------+       +-------------------+       +------------------+
        |                          |
        |                  +-------+-------+
        |                  |               |
        v                  v               v
+------------------+  +---------+  +----------------+
| Apple Frameworks |  |  Redis  |  |  PostgreSQL    |
| - CarPlay        |  |  Cache  |  |  Database      |
| - Speech/AVAudio |  |         |  |                |
| - EventKit       |  +---------+  +----------------+
| - MapKit         |
| - MediaPlayer    |
| - Messages       |
| - WeatherKit     |
+------------------+
```

### Component Responsibilities

| Component | Role |
|-----------|------|
| iOS CarPlay App | Voice capture, CarPlay UI rendering, native framework access |
| Rails Backend | Session management, Claude orchestration, tool dispatch |
| Claude API | Natural language understanding, tool selection, response generation |
| Integrations::Orchestrator | Routes tool calls to adapters, logging, error handling |
| Adapters | Translate tool calls into framework-specific operations |
| Redis | Session cache, vehicle state, rate limiting |
| PostgreSQL | Users, sessions, messages, preferences, credentials |

## Data Flow

### Standard Voice Interaction (No Tools)

```
iOS App          Backend              Claude API
  |                |                      |
  |-- audio ------>|                      |
  |  (transcribed) |                      |
  |                |-- chat_with_tools -->|
  |                |                      |
  |                |<-- text response ----|
  |                |                      |
  |<-- response ---|                      |
  |  (TTS + UI)    |                      |
```

### Voice Interaction with Tool Execution

```
iOS App      Backend            Orchestrator       Adapter         Claude API
  |            |                     |                |                |
  |-- text --->|                     |                |                |
  |            |-- chat_with_tools --|----------------|--------------->|
  |            |                     |                |                |
  |            |<-- tool_use --------|----------------|----------------|
  |            |                     |                |                |
  |            |-- execute_tool_call>|                |                |
  |            |                     |-- execute ---->|                |
  |            |                     |<-- Result -----|                |
  |            |                     |                |                |
  |            |<-- tool_results ----|                |                |
  |            |                     |                |                |
  |            |-- chat (with tool_results) ---------|--------------->|
  |            |                     |                |                |
  |            |<-- final text ------|----------------|----------------|
  |            |                     |                |                |
  |<- response-|                     |                |                |
```

### Detailed Sequence: Navigation Request

```
User: "Navigate to the airport"

1. iOS captures audio, transcribes via Speech framework
2. POST /api/v1/sessions/:id/messages { text: "Navigate to the airport" }
3. ContextManager#process_message:
   a. Saves user message to conversation_messages
   b. Builds system prompt (driving state, preferences, vehicle info)
   c. Sends to Claude with tool definitions
4. Claude responds with tool_use: navigate_to { destination: "the airport" }
5. ContextManager saves assistant message with tool_calls
6. Orchestrator#execute_tool_call("navigate_to", { destination: "the airport" }, user:)
   a. Registry lookup -> MapsAdapter
   b. MapsAdapter#execute validates input, simulates route calculation
   c. Returns Result { success: true, data: { eta: 25, distance: 18.5, ... } }
7. Tool result saved as tool-role message
8. Results sent back to Claude as tool_result content blocks
9. Claude generates final response: "I've started navigation to the airport.
   It should take about 25 minutes."
10. Final assistant message saved
11. Response returned to iOS app for TTS playback
```

## Integration Points with Apple Frameworks

### MapKit (Navigation)

- **Adapter**: `Integrations::MapsAdapter`
- **Tool**: `navigate_to`
- **iOS Side**: The companion app receives navigation instructions via push notification or WebSocket, then uses `MKDirectionsRequest` and `MKMapItem.openMaps(with:)` to launch turn-by-turn navigation in CarPlay.
- **Data**: Destination string, route preferences (avoid highways/tolls)
- **Production Notes**: Would use MapKit JS on the server for geocoding/ETA estimation, with native MapKit on iOS for actual navigation rendering.

### EventKit (Calendar & Reminders)

- **Adapter**: `Integrations::CalendarAdapter`
- **Tools**: `get_calendar_events`, `set_reminder`
- **iOS Side**: The companion app uses `EKEventStore` to query calendars and create reminders. Requires user permission (`NSCalendarsUsageDescription`).
- **Data**: Date ranges, event details, reminder text with time/location triggers
- **Production Notes**: Calendar data is synced to the backend periodically or fetched on-demand via the iOS companion app.

### Messages Framework

- **Adapter**: `Integrations::MessagesAdapter`
- **Tools**: `send_message`, `read_messages`
- **iOS Side**: Uses `MFMessageComposeViewController` for sending (requires user confirmation for safety). Reading uses the companion app's notification access.
- **Data**: Contact name/number, message text, service type (SMS/iMessage)
- **Production Notes**: Message sending always requires user confirmation on the iOS side for privacy and safety. The backend simulates the send and the iOS app handles the actual dispatch.

### MediaPlayer / MusicKit

- **Adapter**: `Integrations::MediaAdapter`
- **Tool**: `play_music`
- **iOS Side**: Uses `MPMusicPlayerController` for Apple Music or SpotifySDK for Spotify. CarPlay audio session management via `AVAudioSession`.
- **Data**: Search query, playback action (play/pause/skip), source
- **Production Notes**: Music search could use Apple Music API server-side; playback control is always iOS-side via the companion app.

### WeatherKit

- **Adapter**: `Integrations::WeatherAdapter`
- **Tool**: `get_weather`
- **iOS Side**: Can use WeatherKit REST API directly from the backend (server-to-server) or relay through the iOS app.
- **Data**: Location, current conditions, forecast
- **Production Notes**: WeatherKit REST API requires an Apple Developer token (JWT). Server-side requests avoid draining device resources.

### Vehicle Integration

- **Adapter**: `Integrations::VehicleAdapter`
- **Tool**: `get_vehicle_status`
- **iOS Side**: Vehicle data comes from OBD-II adapters, manufacturer APIs (e.g., Tesla API, Ford FordPass), or simulated data.
- **Data**: Speed, fuel/battery level, tire pressure, odometer
- **Production Notes**: Uses `VehicleContextService` for cached state. Real-time data pushed from the iOS app via periodic state updates.

## API Contract Specifications

### Tool Call Flow (Internal)

The orchestrator accepts tool calls in the format returned by Claude's API:

```ruby
# Input to Orchestrator#execute_tool_call
tool_name: String        # e.g., "navigate_to"
input: Hash              # e.g., { "destination" => "Airport" }
user: User               # ActiveRecord User instance

# Return value: Integrations::BaseAdapter::Result
{
  success: Boolean,
  data: Hash,            # Tool-specific response data
  error: String | nil    # Error message if success is false
}
```

### Tool Result Format (sent back to Claude)

```json
{
  "type": "tool_result",
  "tool_use_id": "toolu_abc123",
  "content": "{\"success\":true,\"data\":{...},\"error\":null}"
}
```

### Adapter Interface Contract

All adapters inherit from `Integrations::BaseAdapter` and must implement:

```ruby
class MyAdapter < Integrations::BaseAdapter
  def execute(input, user:)
    # input: Hash with string or symbol keys
    # user: User ActiveRecord instance
    # Must return: BaseAdapter::Result (via success_result or error_result)
  end
end
```

### Orchestrator Registry

Adding a new tool requires two steps:

1. Create an adapter class in `app/services/integrations/`
2. Register it in `Integrations::Orchestrator::TOOL_REGISTRY`:

```ruby
TOOL_REGISTRY = {
  "my_new_tool" => { adapter: MyNewAdapter, action: "optional_action" }
}
```

The optional `action` field is injected into the input hash, allowing a single adapter to handle multiple tools (e.g., `CalendarAdapter` handles both `get_calendar_events` and `set_reminder`).

## Error Handling and Retry Strategies

### Error Hierarchy

```
StandardError
  +-- Integrations::BaseAdapter::AdapterError
  |     +-- ValidationError    (invalid input)
  |     +-- TimeoutError       (adapter exceeded timeout)
  |     +-- NotImplementedError (abstract method not overridden)
  +-- Integrations::Orchestrator::UnknownToolError
  +-- Integrations::Orchestrator::ToolExecutionError
```

### Error Handling by Layer

| Layer | Error Type | Behavior |
|-------|-----------|----------|
| Adapter | ValidationError | Returns Result with success=false, does not retry |
| Adapter | TimeoutError | Caught by orchestrator, returns error Result |
| Orchestrator | UnknownToolError | Raised immediately, no retry |
| Orchestrator | AdapterError (any) | Caught, returns error Result to Claude |
| Orchestrator | Unexpected StandardError | Re-raised as ToolExecutionError |
| ContextManager | ToolExecutionError | Caught, returns error array to Claude |
| ClaudeClient | RateLimitError | Retried with exponential backoff (max 3) |
| ClaudeClient | TimeoutError | Retried with exponential backoff (max 3) |

### Timeout Configuration

Each adapter defines its own timeout via `DEFAULT_TIMEOUT`:

| Adapter | Timeout | Rationale |
|---------|---------|-----------|
| MapsAdapter | 15s | Route calculation may be slow |
| CalendarAdapter | 10s | Standard API call |
| MessagesAdapter | 10s | Standard API call |
| MediaAdapter | 10s | Music search + playback |
| WeatherAdapter | 10s | External API call |
| VehicleAdapter | 5s | Local cache lookup, should be fast |

### Retry Strategy

- **Claude API calls**: Exponential backoff with jitter (2^n + random 0-0.5s), max 3 retries
- **Adapter calls**: No automatic retry at the adapter level. If an adapter fails, the error is returned to Claude, which can decide whether to retry or inform the user.
- **Rationale**: In a driving context, latency is critical. Retrying tool calls adds delay, and Claude can provide a graceful fallback response to the user instead.

### Graceful Degradation

When a tool fails, the flow continues:

1. Adapter returns `Result(success: false, error: "...")`
2. Orchestrator logs the failure and returns the error Result
3. Error Result is serialized and sent to Claude as a tool_result
4. Claude interprets the error and generates a user-friendly response
   (e.g., "I wasn't able to start navigation right now. Could you try again?")

This ensures the conversation never breaks due to a tool failure.

## Logging

All tool executions are logged with:
- Tool name
- Adapter class
- Success/failure status
- Latency in milliseconds
- Error message (on failure)

Log format:
```
[Integrations::Orchestrator] tool=navigate_to adapter=Integrations::MapsAdapter success=true latency_ms=12
[Integrations::Orchestrator] tool=send_message adapter=Integrations::MessagesAdapter success=false latency_ms=5 error=Missing required fields: contact
```
