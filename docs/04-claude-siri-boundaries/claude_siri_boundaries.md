# Claude and Siri Boundary Definitions

## Overview

The CarPlay Claude Voice Assistant operates alongside Siri in the vehicle environment. Clear boundaries prevent conflicts, reduce latency, and ensure the driver gets the best response from the right system. This document defines what each system handles, how handoffs work, and how conflicts are resolved.

## What Siri Handles Natively

Siri should remain the primary handler for system-level and Apple-ecosystem commands where it has privileged OS access and lower latency:

### System Commands
- Volume control ("Set volume to 50%")
- Do Not Disturb / Focus modes ("Turn on Do Not Disturb")
- Timer and alarm management ("Set a timer for 10 minutes")
- System settings ("Turn on Bluetooth", "Increase brightness")
- App launching ("Open Maps", "Open Spotify")

### HomeKit
- Smart home device control ("Turn off the living room lights")
- Scene activation ("Set the house to Away mode")
- Thermostat adjustments ("Set the temperature to 72")
- Lock/unlock doors ("Lock the front door")
- Garage door control ("Open the garage door")

### Shortcuts
- User-defined Siri Shortcuts ("Run my morning commute shortcut")
- Automation triggers ("Start my workout playlist")
- Multi-step shortcuts that chain Apple app actions

### Phone and Messaging
- Placing and receiving phone calls ("Call Mom")
- Reading and sending iMessage/SMS ("Read my last message", "Text John I'm on my way")
- FaceTime audio calls

### Navigation (Apple Maps)
- Basic turn-by-turn routing ("Navigate to the nearest gas station")
- ETA queries ("How long until I get home?")
- Traffic conditions for active route

### Media Playback Control
- Play/pause/skip ("Play the next song")
- Playlist and artist requests within Apple Music ("Play Taylor Swift")
- Podcast playback ("Play my podcast")

## What Claude Handles

Claude serves as the intelligent assistant for tasks requiring reasoning, context awareness, and complex conversation:

### Complex Reasoning
- Multi-step problem solving ("What's the best route if I need to stop for gas and pick up groceries, and I want to avoid tolls?")
- Comparative analysis ("Compare the reviews of these two restaurants near my destination")
- Planning and scheduling ("Help me plan a road trip from Austin to Denver with stops every 3 hours")

### Multi-Turn Conversation
- Follow-up questions that require conversational memory ("What about Italian restaurants instead?", "How far is the second one?")
- Clarification dialogs ("When you say 'the usual place', do you mean the downtown location or the one near your office?")
- Progressive refinement of requests through back-and-forth dialog

### Context-Aware Responses
- Responses that consider time of day, location, weather, and driving conditions
- Personalized suggestions based on user preferences and history
- Vehicle-state-aware responses ("Based on your current fuel level, you should stop within the next 40 miles")

### Knowledge and Information
- General knowledge questions ("What year was the Brooklyn Bridge built?")
- Explanations of complex topics ("Explain how regenerative braking works")
- Current events discussion and summarization
- Technical and domain-specific queries

### Driving-Specific Intelligence
- Interpreting and explaining road signs or driving situations described by the user
- Providing contextual safety information ("What should I do if my tire pressure warning comes on?")
- Summarizing long-form content for audio consumption while driving

### Integration Orchestration
- Coordinating across multiple data sources to fulfill a single request
- Querying third-party APIs (weather, traffic, points of interest) and synthesizing results
- Managing multi-service workflows (e.g., finding a restaurant, checking hours, and adding to calendar)

## Handoff Protocol Between Siri and Claude

### Activation Flow

```
Driver presses voice button
       |
       v
  Siri activates (system default)
       |
       v
  Is the utterance a Siri Shortcut for "Ask Claude"?
       |
  YES  |  NO
  |    |    |
  v    |    v
Claude |  Siri processes natively
handles|
  |    |
  v    v
  Does Siri recognize a native intent?
       |
  YES  |  NO
  |    |    |
  v    |    v
Siri   |  Siri returns "I can't help with that"
handles|  App detects fallback -> routes to Claude
```

### Trigger Phrases for Claude

The app registers Siri Shortcuts with these trigger phrases:
- "Ask Claude [question]" -- Direct routing to Claude
- "Hey Claude" -- Shortcut that opens a Claude conversation session
- "Think about this" -- Routes a complex question to Claude

### Siri-to-Claude Handoff

1. **Explicit handoff**: User invokes a registered Siri Shortcut that targets the Claude assistant. Siri passes the transcribed text to the app's intent handler, which forwards it to Claude.

2. **Fallback handoff**: When Siri cannot handle a request, the app listens for the Siri failure callback. If the user has opted in to automatic Claude fallback, the app captures the original transcription and sends it to Claude.

3. **Contextual handoff**: During an active Claude conversation, if the user presses the voice button, Siri activates. If Siri cannot handle the new request and Claude has an active session, the new utterance is appended to the existing Claude conversation context.

### Claude-to-Siri Handoff

When Claude determines a request is better handled by Siri:

1. Claude detects the intent matches a Siri-native capability (system command, HomeKit, phone call).
2. Claude responds with a spoken suggestion: "That's something Siri can handle directly. Would you like me to hand this off to Siri?"
3. If the user confirms, the app triggers the appropriate SiriKit intent programmatically.
4. If programmatic triggering is not possible (some intents require direct Siri invocation), Claude instructs: "Press the voice button and say '[exact Siri command]'."

## Conflict Resolution

When both Siri and Claude could potentially handle a query, the system applies these rules in order:

### Priority Rules

1. **Safety-critical commands always go to Siri** -- Emergency calls ("Call 911"), volume control while navigating, and any command that requires immediate OS-level action.

2. **Active conversation context favors Claude** -- If Claude has an active multi-turn session and the new utterance is contextually related to the ongoing conversation, Claude handles it.

3. **System-level commands always go to Siri** -- Bluetooth, Wi-Fi, brightness, volume, Do Not Disturb, timers, and alarms.

4. **HomeKit commands always go to Siri** -- Smart home control requires HomeKit framework access that only Siri has.

5. **Ambiguous queries use user preference** -- If the user's profile indicates a preference for Claude (stored in UserPreference.custom_settings), ambiguous queries route to Claude. Otherwise, Siri handles first.

6. **Explicit invocation overrides all rules** -- "Ask Claude..." always goes to Claude. "Hey Siri..." always goes to Siri.

### Conflict Detection Heuristics

The app maintains a classification layer that examines the utterance before routing:

| Signal | Routes To |
|---|---|
| Contains "Claude" or "ask Claude" | Claude |
| Contains "Siri" or "Hey Siri" | Siri |
| Matches a registered SiriKit intent domain keyword | Siri |
| Contains follow-up markers ("what about", "instead", "also") with active Claude session | Claude |
| Contains system keywords ("volume", "brightness", "bluetooth", "timer") | Siri |
| Contains HomeKit device names from user's home configuration | Siri |
| Question length > 20 words | Claude |
| Contains reasoning keywords ("why", "how does", "compare", "explain", "help me plan") | Claude |

### Fallback Behavior

- If Claude is unavailable (network error, timeout > 10 seconds), the app informs the driver via audio: "Claude is temporarily unavailable. You can ask Siri instead, or I'll retry in a moment."
- If Siri fails and Claude fallback is enabled, Claude receives the utterance within 500ms of the Siri failure callback.
- If both systems fail, the app provides a clear audio message and does not retry silently.

## SiriKit Intent Domains vs Claude Capabilities Matrix

| Domain / Capability | Siri | Claude | Preferred Handler | Notes |
|---|---|---|---|---|
| **Messaging** | | | | |
| Send SMS/iMessage | Yes | No | Siri | OS-level messaging access |
| Compose complex message | Limited | Yes | Claude | Claude drafts, Siri sends |
| Summarize unread messages | No | Yes | Claude | Requires message content access |
| **VoIP Calling** | | | | |
| Place call to contact | Yes | No | Siri | Direct telephony access |
| Find best time to call someone | No | Yes | Claude | Reasoning about schedules |
| **Audio Playback** | | | | |
| Play song/artist/playlist | Yes | No | Siri | Apple Music / media framework |
| Recommend music based on mood | No | Yes | Claude | Contextual reasoning |
| Explain a song's lyrics | No | Yes | Claude | Knowledge and analysis |
| **Navigation** | | | | |
| Point-to-point routing | Yes | No | Siri | MapKit integration |
| Multi-stop trip planning | Limited | Yes | Claude | Complex optimization |
| "What's nearby that's good?" | Limited | Yes | Claude | Subjective reasoning |
| Explain traffic situation | No | Yes | Claude | Contextual narrative |
| **Car Commands** | | | | |
| Lock/unlock vehicle | Yes | No | Siri | CarKey framework |
| Explain dashboard warning light | No | Yes | Claude | Knowledge base |
| Diagnose unusual car behavior | No | Yes | Claude | Reasoning and knowledge |
| **Smart Home (HomeKit)** | | | | |
| Control devices | Yes | No | Siri | HomeKit framework |
| Set up automation rules | Limited | Yes | Claude | Complex logic |
| Troubleshoot devices | No | Yes | Claude | Diagnostic reasoning |
| **General Knowledge** | | | | |
| Simple factual lookup | Limited | Yes | Claude | Better accuracy and depth |
| Complex explanation | No | Yes | Claude | Multi-paragraph reasoning |
| Math and calculation | Limited | Yes | Claude | Higher reliability |
| **Planning** | | | | |
| Set timer/alarm | Yes | No | Siri | System clock access |
| Plan multi-day itinerary | No | Yes | Claude | Complex planning |
| Calendar event creation | Yes | No | Siri | EventKit access |
| Schedule optimization | No | Yes | Claude | Reasoning over constraints |
| **Vehicle Context** | | | | |
| Read vehicle sensor data | No | No | App | Direct OBD/vehicle API |
| Interpret sensor readings | No | Yes | Claude | Explain what readings mean |
| Fuel/charge stop planning | Limited | Yes | Claude | Optimization with context |
| **Conversation** | | | | |
| Single-turn Q&A | Limited | Yes | Claude | Better comprehension |
| Multi-turn dialog | No | Yes | Claude | Context retention |
| Personality and rapport | No | Yes | Claude | Conversational style |
| Context from previous drives | No | Yes | Claude | Long-term memory |
