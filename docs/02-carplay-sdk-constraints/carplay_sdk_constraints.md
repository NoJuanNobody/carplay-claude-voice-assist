# CarPlay SDK Constraints

## CarPlay App Types

Apple restricts CarPlay to five approved app categories. Each category has distinct entitlements and UI capabilities:

| App Type | Entitlement | Primary Use |
|---|---|---|
| Navigation | `com.apple.developer.carplay-maps` | Turn-by-turn directions, map display, route planning |
| Audio | `com.apple.developer.carplay-audio` | Music, podcasts, audiobooks, radio streaming |
| Communication | `com.apple.developer.carplay-communication` | Messaging, VoIP calling |
| EV Charging | `com.apple.developer.carplay-charging` | Locate and manage EV charging stations |
| Driving Task | `com.apple.developer.carplay-driving-task` | Parking, road conditions, toll management, vehicle accessories |

For the Claude Voice Assistant, the **Communication** category is the most appropriate, as voice-based conversational interaction aligns with the communication entitlement. A secondary **Driving Task** entitlement may apply if the app surfaces driving-relevant information (e.g., road conditions via Claude).

## Template Limitations

CarPlay apps cannot use custom UIKit views on the car display. All UI must be built from Apple-provided CPTemplate subclasses:

### Available Templates

1. **CPListTemplate** -- Scrollable list of items with text, images, and accessory indicators. Maximum of 12 visible items per section. Supports hierarchical navigation (push/pop).

2. **CPGridTemplate** -- Grid of buttons (max 8 buttons). Each button has a title and an image. No subtitle or accessory support.

3. **CPTabBarTemplate** -- Tab-based navigation container. Maximum of 4 tabs on most vehicle displays; 5 tabs on wide displays. Each tab wraps another template.

4. **CPAlertTemplate** -- Modal alert with a title, optional body text, and up to 2 action buttons. Dismissed automatically after a timeout or user interaction.

5. **CPActionSheetTemplate** -- Bottom sheet with a title, optional message, and up to 3 action buttons. Used for contextual choices.

6. **CPInformationTemplate** -- Displays labeled key-value items (max 10 rows) with up to 3 action buttons. Read-only display of structured information.

7. **CPPointOfInterestTemplate** -- Shows a map with up to 12 annotated points of interest. Each POI has a title, subtitle, and detail text.

### Template Rules

- Only one template can be visible at a time (aside from alerts/action sheets which overlay).
- Template stack depth is limited to 5 levels of push navigation.
- Templates cannot be customized beyond the properties Apple exposes (no custom fonts, colors beyond tint, or layouts).
- Image assets must be provided in template-specific sizes (typically 44x44pt to 90x90pt) and are rendered by the car's display system.

## Screen Size Constraints

CarPlay vehicle displays vary significantly:

| Display Category | Resolution Range | Aspect Ratio |
|---|---|---|
| Standard | 800x480 | ~5:3 |
| Wide | 1280x480 | ~8:3 |
| Ultrawide | 1920x720 | ~8:3 |
| Cluster (instrument) | 480x360 | ~4:3 |

Key constraints:
- Apps must support all display sizes through CarPlay's automatic layout system.
- No pixel-level positioning is available; templates handle layout.
- Text is truncated automatically; titles should be kept under 30 characters for reliable display.
- High-DPI (2x, 3x) assets should be provided but will be scaled by the system.
- Dark mode is always active on CarPlay; apps do not control light/dark appearance.

## Button and Interaction Limits

- **CPListTemplate**: Each list item can have one primary action (tap) and one trailing accessory button.
- **CPGridTemplate**: Maximum 8 grid buttons.
- **CPAlertTemplate**: Maximum 2 action buttons.
- **CPActionSheetTemplate**: Maximum 3 action buttons.
- **CPInformationTemplate**: Maximum 3 action buttons.
- **CPNowPlayingTemplate**: System-managed playback controls; apps add up to 4 custom buttons.
- **Bar buttons**: Navigation bar supports up to 2 leading and 2 trailing bar button items.
- All buttons must have large-enough tap targets (minimum 44x44pt equivalent) for safe in-vehicle use.
- No text input is permitted on the CarPlay display; all text entry must go through Siri voice input.

## Siri Integration Points and Limitations

### SiriKit Intent Domains Available to CarPlay

| Intent Domain | Example Intents | CarPlay Support |
|---|---|---|
| Messaging | Send message, search messages | Full |
| VoIP Calling | Start call, search call history | Full |
| Audio Playback | Play media, add to library | Full |
| Navigation | Get directions, set destination | Full |
| Car Commands | Lock/unlock, get car status | Full |
| EV Charging | Find charging station | Full |

### Siri Integration Points

1. **SiriKit Intents** -- Register intent handlers via the Intents app extension. CarPlay routes voice requests matching registered domains to the app's intent handler.

2. **Siri Shortcuts** -- Custom intents defined in the app's intent definition file. Users can create voice-triggered shortcuts for specific app actions. Requires explicit user setup.

3. **Voice activation** -- Users say "Hey Siri" or press the voice button on the steering wheel. The system routes to Siri first; Siri either handles natively or delegates to the app's intent handler.

4. **Inline voice feedback** -- Apps can provide custom response templates (dialog and snippet) that Siri speaks and displays after handling an intent.

### Siri Limitations

- Siri always intercepts the voice button press first; apps cannot bypass Siri to receive raw audio directly.
- Custom intents are limited in parameter types (string, integer, boolean, enum, person, file) and cannot accept complex structured data.
- Siri timeouts: intent handlers must respond within 10 seconds or Siri shows an error.
- No streaming responses: Siri expects a single complete response, not incremental updates.
- Background audio sessions may be interrupted when Siri activates.
- Siri's natural language understanding is opaque; apps cannot influence how Siri parses utterances beyond defining intent parameter vocabularies.

## Voice-First Interaction Requirements

CarPlay is a voice-first environment. Apple mandates:

1. **Minimal visual interaction** -- Drivers must not need to look at the screen for more than 1-2 seconds per glance. All essential information must be accessible via voice.

2. **No typing** -- Text input fields are prohibited on the CarPlay display. Use Siri dictation or predefined choices.

3. **Glanceable UI** -- Screen content must be readable in under 2 seconds. Use short labels, large icons, and minimal information density.

4. **Audio feedback** -- Provide spoken confirmation for all actions. Do not rely on visual-only feedback.

5. **Interruptibility** -- Voice interactions must be cancellable at any time (e.g., user presses the steering wheel button again). The app must handle interruption gracefully.

6. **Conversation continuity** -- If a multi-turn conversation is interrupted by a phone call or navigation announcement, the app should be able to resume context.

7. **Ambient noise handling** -- Voice input in a car is noisy. Provide clear reprompts and confirmation for critical actions.

## Apple Review Guidelines for CarPlay Apps

### Mandatory Requirements

- **Entitlement approval**: Apps must apply for and receive a CarPlay entitlement from Apple before submission. This is a manual review process separate from App Store review.

- **Distraction minimization**: Apps must follow the CarPlay Human Interface Guidelines (HIG). Reviewers specifically check for excessive interaction depth, dense text, and animations.

- **Template-only UI**: Any attempt to render custom views on the CarPlay display will result in rejection. Only CPTemplate subclasses are permitted.

- **Appropriate category**: Apps must request only the entitlement(s) matching their functionality. A music app requesting the navigation entitlement will be rejected.

### Common Rejection Reasons

1. **Too many taps to reach core functionality** -- Apple expects primary actions to be reachable within 2 taps from the root template.

2. **Excessive list length** -- Lists with more than 12-15 items without clear categorization or search.

3. **Missing voice support** -- Core features that cannot be accessed via Siri or voice commands.

4. **Inappropriate content** -- Video playback, games, or any content encouraging extended screen interaction while driving.

5. **Missing iPhone companion** -- The CarPlay UI must be a complement to the iPhone app, not a standalone experience. The iPhone app must provide full functionality.

6. **Performance** -- Templates must load within 2 seconds. Slow network requests without loading indicators will be rejected.

### Best Practices for Approval

- Keep the template hierarchy shallow (2-3 levels maximum).
- Provide Siri Shortcuts for the top 3-5 most common actions.
- Include a "Now Playing"-style persistent template for ongoing voice conversations.
- Test on multiple CarPlay simulator display sizes before submission.
- Include a CarPlay-specific section in the App Store description explaining the in-car experience.
- Provide a demo video showing the CarPlay experience during the review process.
