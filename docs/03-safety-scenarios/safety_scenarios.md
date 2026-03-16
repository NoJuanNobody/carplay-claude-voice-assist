# Safety Scenarios

## Overview

Driver safety is the non-negotiable top priority of the CarPlay Claude Voice Assistant. Every interaction is governed by the current driving state, and the system is designed to minimize cognitive load, reduce visual distraction, and defer non-critical tasks until the vehicle is stationary.

This document defines the driving state classification system, response constraints per state, prohibited actions, emergency protocols, and a comprehensive scenario matrix covering 20+ specific situations.

---

## 1. Driving State Classification

### 1.1 State Definitions

The assistant classifies the vehicle's state into one of four categories using a combination of signals from CoreMotion, CarPlay session state, and (where available) vehicle speed data via the OBD-II or CAN bus integration.

| State | Criteria | Confidence Requirement |
|---|---|---|
| **Parked** | Speed = 0 AND transmission in Park (or stationary > 30s) | High (two confirming signals) |
| **City** | Speed > 0 AND speed <= 45 mph | Medium (speed alone sufficient) |
| **Highway** | Speed > 45 mph | Medium (speed alone sufficient) |
| **Emergency** | Hazard lights on, collision detected, or user says emergency keyword | Any single signal sufficient |

### 1.2 State Detection Signals

```swift
enum DrivingStateSignal {
    case coreMotionActivity(CMMotionActivity)  // Automotive, stationary
    case vehicleSpeed(Double)                   // mph, from CarPlay or OBD-II
    case carplaySessionActive(Bool)             // CarPlay connected
    case transmissionState(TransmissionState)   // Park, Drive, Reverse, Neutral
    case accelerometerVariance(Double)          // Movement detection fallback
    case hazardLightsActive(Bool)               // Emergency signal
    case collisionDetected(Bool)                // Crash detection (if available)
}
```

### 1.3 State Transition Debouncing

To avoid rapid state changes (e.g., stopping at a red light should not trigger "Parked" mode), the following debounce rules apply:

- **To Parked:** Vehicle must be stationary for 30 continuous seconds
- **City to Highway:** Speed must exceed 45 mph for 10 continuous seconds
- **Highway to City:** Speed must drop below 40 mph for 10 continuous seconds (5 mph hysteresis to prevent oscillation)
- **To Emergency:** No debounce; transitions immediately on any emergency signal
- **From Emergency:** Requires explicit user dismissal or 5 minutes without emergency signals

### 1.4 Unknown State Handling

If the driving state cannot be determined (e.g., no speed data, no motion data), the system defaults to **Highway** mode (most restrictive). This ensures safety-first behavior when sensor data is unavailable.

---

## 2. Response Length Limits

### 2.1 Limits by Driving State

| Driving State | Max Response Length | Max Response Duration (TTS) | Visual Content | Interaction Depth |
|---|---|---|---|---|
| **Parked** | Unlimited | Unlimited | Full UI | Multi-step flows allowed |
| **City** | 2 sentences | ~10 seconds | 2 list rows max | Single confirmation only |
| **Highway** | 1 sentence | ~5 seconds | 1 row or status indicator | No confirmations; auto-commit or defer |
| **Emergency** | Critical info only | ~3 seconds | Emergency UI only | None; system-driven actions only |

### 2.2 Response Truncation Strategy

When Claude's response exceeds the length limit for the current driving state, the system applies intelligent truncation:

1. **Summarization pass:** The full response is re-processed with a summarization prompt appropriate for the word limit
2. **Key information extraction:** Critical facts (numbers, names, yes/no answers) are prioritized
3. **Deferral offer:** If truncation would lose important information, the assistant says: "I have more details. Want me to continue when you're parked?"
4. **Queue for later:** Full response is stored and delivered when the driver reaches Parked state

```swift
struct ResponseConstraints {
    let maxSentences: Int?        // nil = unlimited
    let maxTTSDuration: TimeInterval?
    let maxListRows: Int
    let allowsMultiStep: Bool
    let allowsConfirmation: Bool

    static let parked = ResponseConstraints(
        maxSentences: nil, maxTTSDuration: nil,
        maxListRows: .max, allowsMultiStep: true, allowsConfirmation: true
    )
    static let city = ResponseConstraints(
        maxSentences: 2, maxTTSDuration: 10,
        maxListRows: 2, allowsMultiStep: false, allowsConfirmation: true
    )
    static let highway = ResponseConstraints(
        maxSentences: 1, maxTTSDuration: 5,
        maxListRows: 1, allowsMultiStep: false, allowsConfirmation: false
    )
    static let emergency = ResponseConstraints(
        maxSentences: 1, maxTTSDuration: 3,
        maxListRows: 0, allowsMultiStep: false, allowsConfirmation: false
    )
}
```

---

## 3. Prohibited Actions While Driving

### 3.1 Absolute Prohibitions (All Non-Parked States)

The following actions are blocked entirely when the vehicle is in motion:

| Prohibited Action | Reason | Alternative Offered |
|---|---|---|
| Reading long text passages (> 2 sentences) | Extended cognitive engagement | "I'll save this for when you're parked" |
| Multi-step confirmation flows | Sequential decision-making increases distraction | Auto-select safe default or defer |
| Displaying scrollable content | Visual distraction, manual interaction | Voice summary only |
| Complex calculations requiring user verification | Cognitive load | Provide single answer without walkthrough |
| Editing or composing long messages | Extended engagement | "I'll draft it; you can review when parked" |
| Displaying images or media | Visual distraction | Describe verbally if relevant |
| Settings changes | Non-urgent, requires attention | "Reminder set to change settings when parked" |

### 3.2 Highway-Specific Additional Prohibitions

| Prohibited Action | Reason |
|---|---|
| Any confirmation prompts ("Did you mean...?") | At highway speed, default to safest interpretation |
| List selection ("Which one: A, B, or C?") | Present top result only |
| Follow-up questions | Answer with best available information and close |
| Non-critical notifications | Suppress until speed < 45 mph |

### 3.3 Implementation: Action Gate

Every assistant action passes through the `SafetyGate` before execution:

```swift
struct SafetyGate {
    static func evaluate(action: AssistantAction, state: DrivingState) -> SafetyVerdict {
        switch (action.category, state) {
        case (.readLongText, .city), (.readLongText, .highway), (.readLongText, .emergency):
            return .blocked(reason: "Long text reading prohibited while driving",
                          alternative: .deferUntilParked)
        case (.multiStepFlow, .highway), (.multiStepFlow, .emergency):
            return .blocked(reason: "Multi-step flows prohibited at highway speed",
                          alternative: .autoSelectDefault)
        case (.displayList, .highway) where action.listItemCount > 1:
            return .modified(action: action.truncatedToSingleItem())
        case (_, .emergency) where !action.isEmergencyRelevant:
            return .blocked(reason: "Non-emergency actions suppressed",
                          alternative: .suppressEntirely)
        default:
            return .allowed
        }
    }
}
```

---

## 4. Emergency Detection and Response Protocol

### 4.1 Emergency Triggers

The system enters Emergency state upon detecting any of the following:

| Trigger | Source | Confidence |
|---|---|---|
| User says "emergency", "help", "crash", "accident", "call 911" | STT keyword detection | High |
| Sudden deceleration > 4G | CoreMotion accelerometer | Medium (requires corroboration) |
| Hazard lights activated | CarPlay vehicle data (where available) | High |
| Airbag deployment signal | Vehicle CAN bus (where available) | Critical |
| User presses emergency button in UI | CarPlay touch input | High |

### 4.2 Emergency Response Sequence

When Emergency state is entered:

```
T+0.0s  Emergency state activated
T+0.0s  All non-critical audio/interactions immediately halted
T+0.5s  Emergency UI displayed: large "Emergency" indicator + "Call 911" button
T+0.5s  TTS: "Emergency detected. Do you need me to call 911?"
T+3.0s  If no response: "Say 'yes' to call 911, or 'cancel' if you're okay"
T+8.0s  If no response and crash detected: Auto-dial 911 (per Apple Crash Detection protocol)
T+8.0s  If no response and no crash: Remain in emergency UI, repeat prompt at 15s intervals
```

### 4.3 Emergency Information Provided to 911

If the user confirms a 911 call (or auto-dial triggers), the system prepares the following information for the dispatcher:

- Approximate location (reverse geocoded from last known GPS, spoken as street address)
- Time of incident
- Number of occupants (if previously configured by user)
- Vehicle description (if previously configured)

This information is displayed on the CarPlay screen and spoken by TTS so the user can relay it verbally to the dispatcher.

### 4.4 Post-Emergency Behavior

After Emergency state is exited:

1. A safety check prompt is offered: "Are you okay to continue driving?"
2. If the user says no, the assistant offers to find the nearest safe stopping point
3. An incident log entry is created on-device (timestamp, duration, trigger type)
4. Normal driving state detection resumes after explicit user confirmation

---

## 5. Distraction Mitigation Strategies

### 5.1 Conversation Pacing

- **Minimum gap between interactions:** 3 seconds (prevents rapid-fire exchanges while driving)
- **Maximum assistant speaking time:** Governed by driving state limits (Section 2)
- **No unsolicited speech:** The assistant never initiates conversation while driving unless responding to an emergency or a pre-scheduled reminder
- **Ambient listening timeout:** If the wake word is detected but no query follows within 5 seconds, the session is silently cancelled (no audio feedback to avoid distraction)

### 5.2 Cognitive Load Estimation

The system estimates cognitive load based on the complexity of the current interaction:

| Load Level | Example | Driving State Restrictions |
|---|---|---|
| Low | "What's the weather?" | Allowed in all states |
| Medium | "Find a gas station nearby" | Allowed in City, simplified in Highway |
| High | "Compare these two restaurants" | Parked only |
| Critical | "Help, I'm lost and low on fuel" | Emergency-relevant, allowed in all states |

### 5.3 Proactive Deferral

The assistant proactively defers complex interactions:

- If a query would require a response longer than the current state allows, the assistant immediately says: "That's a detailed answer. I'll have it ready when you park. Quick version: [1-sentence summary]."
- Deferred items are queued and presented (via a gentle audio chime + spoken summary) when the vehicle enters Parked state.

### 5.4 Glance-Time Compliance

All visual elements comply with Apple's CarPlay Human Interface Guidelines and NHTSA visual-manual distraction guidelines:

- **Maximum glance time:** 2 seconds per interaction (single glance)
- **Total eyes-off-road time:** < 12 seconds per task (cumulative)
- **Font size:** Minimum 24pt for primary text on CarPlay display
- **Touch targets:** Minimum 44x44 pt (Apple HIG requirement)
- **Animation:** No animations that attract gaze; static or minimal transitions only

---

## 6. Safety Event Logging and Reporting

### 6.1 Logged Events

| Event | Data Captured | Retention |
|---|---|---|
| Emergency state activation | Timestamp, trigger type, duration | 90 days |
| Safety gate block | Timestamp, blocked action type, driving state | 30 days |
| Response truncation | Timestamp, original length, truncated length | 30 days |
| State transition | Timestamp, from-state, to-state | 7 days |
| Unknown state fallback | Timestamp, available signals, fallback state used | 30 days |

### 6.2 Privacy of Safety Logs

Safety logs contain no conversation content, audio data, or location information. They record only event types, timestamps, and driving states. All logs are stored on-device with `NSFileProtectionComplete` and are subject to the retention schedule in the Privacy Framework (Issue #5).

### 6.3 Aggregate Safety Reporting

If the user opts in to anonymized analytics, the following aggregated metrics are reported:

- Count of emergency activations per month
- Count of safety gate blocks per driving state
- Distribution of driving states during assistant usage
- Average response length by driving state

These metrics help improve the safety system but contain no personally identifiable information.

---

## 7. UI Compliance Rules

### 7.1 CarPlay Human Interface Guidelines (HIG)

| Rule | Requirement | Implementation |
|---|---|---|
| Maximum list rows (driving) | 2 rows | `CPListTemplate` limited to 2 items when driving state != Parked |
| Maximum list rows (parked) | 12 rows | Full list available when parked |
| Tab bar items | Maximum 4 | App uses 3 tabs: Assistant, History, Settings |
| Grid layout | Maximum 8 buttons | Not used; voice-first interface |
| No keyboard input while driving | System-enforced | Text input fields only available when parked |
| Alert duration | Auto-dismiss after 10 seconds | `CPAlertTemplate` with timer |
| No video playback | System-enforced | Not applicable |

### 7.2 Template Usage by Driving State

| Driving State | Allowed Templates | Prohibited Templates |
|---|---|---|
| Parked | All CPTemplates | None |
| City | `CPVoiceControlTemplate`, `CPListTemplate` (2 rows), `CPAlertTemplate` | `CPInformationTemplate`, `CPGridTemplate` |
| Highway | `CPVoiceControlTemplate`, `CPNowPlayingTemplate` (status only) | All interactive templates |
| Emergency | `CPAlertTemplate` (emergency variant only) | All others |

### 7.3 Dark Mode and Readability

- All UI elements support both light and dark CarPlay appearances
- Contrast ratios meet WCAG 2.1 AA standards (4.5:1 for normal text, 3:1 for large text)
- No color is used as the sole means of conveying information (accessibility compliance)

---

## 8. Scenario Matrix

The following matrix covers 20+ specific scenarios with the expected assistant behavior for each driving state.

### 8.1 Information Queries

| # | Scenario | Parked | City | Highway | Emergency |
|---|---|---|---|---|---|
| 1 | "What's the weather?" | Full forecast with details | "Sunny, 72 degrees, no rain today." | "72 and sunny." | Suppressed |
| 2 | "Read my last email" | Reads full email text | "Email from [name]: [2-sentence summary]" | "You have an email from [name]. I'll read it when you park." | Suppressed |
| 3 | "What's the score of the game?" | Full box score and commentary | "Lakers lead 98-92, 4th quarter." | "Lakers up 98-92." | Suppressed |
| 4 | "Tell me about this podcast episode" | Full description | 2-sentence summary | "It's about [topic]. Details when you park." | Suppressed |

### 8.2 Navigation and Location

| # | Scenario | Parked | City | Highway | Emergency |
|---|---|---|---|---|---|
| 5 | "Find a gas station" | List of 5 nearest with details | "Nearest Shell is 0.3 miles ahead on your right." | "Shell, 0.3 miles ahead." | "Nearest gas station is [distance] [direction]." |
| 6 | "How far to home?" | Full route details with options | "42 minutes, 28 miles via I-95." | "42 minutes to home." | Route info if relevant |
| 7 | "Find a restaurant for dinner" | List with ratings, reviews, distance | "Nearest highly-rated: [name], 0.5 miles." | "Good restaurant 0.5 miles ahead." | Suppressed |
| 8 | "Is there traffic ahead?" | Detailed traffic map description | "Slowdown in 2 miles, 10-minute delay." | "10-minute delay ahead." | Traffic info if relevant |

### 8.3 Communication

| # | Scenario | Parked | City | Highway | Emergency |
|---|---|---|---|---|---|
| 9 | "Send a message to Mom" | Full compose flow with editing | "What should I say?" then send on confirmation | "What should I say?" then auto-send | Suppressed |
| 10 | "Call John" | Initiate call | Initiate call | Initiate call | Initiate call (allowed in all states) |
| 11 | "Read all my notifications" | Reads all notifications | "You have 5 notifications. Top two: [summaries]" | "5 notifications. Most important: [1 summary]" | Suppressed |
| 12 | "Reply to that text" | Full compose flow | "What's your reply?" then send | "Quick reply: what should I say?" then auto-send | Suppressed |

### 8.4 Complex Queries

| # | Scenario | Parked | City | Highway | Emergency |
|---|---|---|---|---|---|
| 13 | "Compare iPhone 16 vs Pixel 9" | Full comparison (multiple paragraphs) | "Key difference: [2 sentences]. More when you park." | "I'll compare those when you park." | Suppressed |
| 14 | "Explain quantum computing" | Full educational response | "In short: [2-sentence summary]. Want the full version when you park?" | "I'll explain when you park." | Suppressed |
| 15 | "What should I cook for dinner?" | Multiple suggestions with recipes | "How about pasta? Quick and easy." | "Pasta is a good quick option." | Suppressed |

### 8.5 Vehicle and Safety

| # | Scenario | Parked | City | Highway | Emergency |
|---|---|---|---|---|---|
| 16 | "My tire pressure light is on" | Full explanation + nearest service centers | "Your tire pressure is low. Nearest service: [name], [distance]." | "Low tire pressure. Service station [distance] ahead. Drive carefully." | "Pull over safely. Nearest service: [distance]." |
| 17 | "I'm feeling drowsy" | Suggest rest, find nearby rest stops | "Rest stop in 3 miles. Please pull over soon." | "Rest stop 3 miles ahead. Please pull over as soon as safe." | Enter Emergency: "Pulling up rest stops. Please pull over safely." |
| 18 | "Call 911" | Initiate call | Initiate call | Initiate call | Initiate call (highest priority) |
| 19 | "I think I'm lost" | Full route recalculation with options | "You're at [location]. Rerouting home now." | "Rerouting home. Follow directions." | "You're near [landmark]. Rerouting now." |
| 20 | "There's a strange noise from the engine" | Describe possible causes, find mechanics | "Could be several things. Nearest mechanic: [name], [distance]." | "Find a safe place to pull over. Mechanic [distance] away." | Enter caution mode: "Please pull over when safe." |

### 8.6 Edge Cases

| # | Scenario | Parked | City | Highway | Emergency |
|---|---|---|---|---|---|
| 21 | User asks assistant to tell a long joke | Full joke | "Here's a quick one: [short joke]" | "How about a joke when you park?" | Suppressed |
| 22 | Rapid repeated queries (potential child playing) | Normal response | Rate limit: 1 response per 5 seconds | Rate limit: 1 response per 10 seconds | Suppressed |
| 23 | Unintelligible speech / noise | "Sorry, I didn't catch that. Could you repeat?" | "Didn't catch that. Try again?" | Silently discard (no distraction) | "Didn't catch that." (once, then silent) |
| 24 | Assistant detects elevated stress in speech | Normal response + "Is everything okay?" | "Is everything alright?" | Note internally, respond normally | Offer emergency assistance |
| 25 | User asks to change a safety setting | Allow full settings access | "Safety settings can only be changed when parked." | "Safety settings can only be changed when parked." | Suppressed |

---

## 9. Fallback Behaviors When Safety State Is Unknown

### 9.1 Default to Most Restrictive

When the driving state cannot be determined, the system assumes **Highway** mode:

- 1-sentence responses maximum
- No confirmations or multi-step flows
- No interactive list displays
- Voice-only interaction

### 9.2 Unknown State Triggers

| Condition | Fallback | Recovery |
|---|---|---|
| No speed data available | Highway mode | Resolves when speed data resumes |
| CoreMotion unavailable | Highway mode (if CarPlay connected) | Resolves when motion data resumes |
| Conflicting signals (e.g., speed=0 but motion detected) | City mode | Resolves after 30s of consistent signals |
| CarPlay disconnected mid-session | Pause all interactions | Resume when CarPlay reconnects |
| Sensor timeout (no data for > 10s) | Retain last known state for 60s, then Highway | Resolves when sensor data resumes |

### 9.3 State Recovery Announcement

When transitioning out of an unknown/fallback state, the assistant does not announce the change (to avoid distraction). Behavior simply adjusts to match the newly determined state. Deferred responses queued during the restrictive fallback are delivered when appropriate.

---

## 10. Safety Testing Requirements

### 10.1 Automated Testing

Every pull request must pass the following safety-related test suites:

- **State classification tests:** 100+ scenarios verifying correct state detection from signal combinations
- **Response truncation tests:** Verify responses are correctly limited per driving state
- **Safety gate tests:** Verify all prohibited actions are blocked in appropriate states
- **Emergency flow tests:** End-to-end emergency detection and response sequence
- **Debounce tests:** Verify state transitions honor debounce timing
- **Fallback tests:** Verify correct behavior when signals are missing or conflicting

### 10.2 Manual Testing (Pre-Release)

- Simulated driving sessions with controlled speed profiles
- Emergency scenario walkthroughs with real CarPlay hardware
- Edge case testing: rapid state transitions, sensor dropout, signal conflicts
- Accessibility testing: VoiceOver compatibility in all driving states
- Glance-time measurement using eye-tracking equipment (per NHTSA guidelines)

### 10.3 Safety Regression Policy

Any change to the safety system requires:

1. Sign-off from the safety engineering lead
2. Full safety test suite pass (automated)
3. Manual verification of the affected scenario(s)
4. Updated scenario matrix entry if behavior changes
