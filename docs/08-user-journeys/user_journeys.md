# User Journey Maps — CarPlay Claude Voice Assistant

## Journey 1: The Daily Commuter

**Persona**: Sarah, 34, software engineer, 45-minute commute each way in a mid-size sedan.

### Context
Sarah drives from her suburban home to a downtown office five days a week. She uses her commute for catching up on news, planning her day, and unwinding on the way home.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Morning departure** | Plugs in iPhone, CarPlay launches | Claude greets: "Good morning, Sarah. Traffic on I-85 is heavier than usual — want me to route via Peachtree instead? You have a 9:30 standup." | CarPlay voice + display |
| **En route** | Asks about schedule | "What's my day look like?" — Claude reads calendar with context: "You have back-to-back meetings from 10 to 12, then lunch is free. Want me to suggest a restaurant near the office?" | Voice conversation |
| **Traffic delay** | Stuck in unexpected congestion | Claude proactively: "There's a 15-minute delay ahead due to an accident. I've found an alternate route that saves 8 minutes. Want me to switch?" | Proactive notification |
| **Arrival** | Approaching office parking | Claude: "You're 5 minutes away. Your first meeting is in Conference Room B. I'll stop here — have a great morning." | Auto wind-down |
| **Evening commute** | Heading home, tired | "Play something relaxing" — Claude selects a playlist based on mood history, then: "Your partner sent a message: 'picking up groceries, need anything?'" | Voice + media control |
| **Errands** | Needs to stop for gas | "Where's the cheapest gas nearby?" — Claude finds stations along the route, compares prices, and navigates to the best option. | Voice + navigation |

### Key Outcomes
- Time saved: ~10 min/day from proactive routing
- Reduced phone interaction: zero screen touches during commute
- Improved morning preparedness: calendar briefing without checking phone

---

## Journey 2: The Road Tripper

**Persona**: Marcus, 29, freelance photographer, drives across the Southwest for landscape shoots.

### Context
Marcus takes 8-12 hour road trips several times a month, often through areas with limited cellular coverage. He needs an assistant that works offline and helps with long-distance planning.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Trip planning** | Before departure | "I'm driving from Phoenix to Monument Valley tomorrow, leaving at 6 AM. Plan my stops." Claude creates a stop plan: fuel, food, scenic viewpoints with estimated times. | Voice + display |
| **Long stretch** | 3 hours in, monotony setting in | "Tell me something interesting about this area." Claude shares local history, geology facts about the Painted Desert based on GPS location. | Conversational |
| **Low connectivity** | Enters a dead zone | Claude seamlessly switches to on-device mode: "I'm offline now, but I have your route cached. I can still help with basic questions and alerts." | On-device fallback |
| **Fuel planning** | Quarter tank remaining | Claude proactively: "You have about 90 miles of range. The next gas station is in 45 miles at Tuba City. After that it's 80 miles to the next one. I'd recommend stopping." | Proactive alert |
| **Photo opportunity** | Sunset approaching | "When's golden hour here?" Claude calculates based on GPS and date: "Golden hour starts at 6:23 PM, about 40 minutes from now. There's a scenic overlook 12 miles ahead." | Location-aware |
| **Accommodation** | Getting late | "Find me somewhere to stay near Monument Valley under $120." Claude searches, filters, reads reviews, and books — all hands-free. | Voice + booking |
| **End of day** | Parked at hotel | Claude: "Great trip today — 487 miles. I'll save this route in case you want to do it again. Rest well." | Session summary |

### Key Outcomes
- Safety: fuel and rest reminders on long stretches
- Enriched experience: contextual storytelling replaces empty silence
- Offline resilience: assistant remains useful without connectivity

---

## Journey 3: The Delivery Driver

**Persona**: Priya, 41, Amazon Flex driver, completes 30-50 deliveries per shift.

### Context
Priya drives 6-8 hours per day making deliveries. She needs efficient routing, quick address lookup, and hands-free package management.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Shift start** | Loads packages, starts route | "I have 42 packages today. Optimize my route." Claude reorders the delivery sequence for minimal driving time and groups nearby stops. | Voice + display |
| **Navigation** | Approaching delivery | Claude: "Next stop is 1247 Oak Street, apartment 3B. Gate code from last time was 4521. Leave at front door per customer instructions." | Proactive context |
| **Problem delivery** | Can't find address | "I can't find 891 Elm Court." Claude: "That address was recently renumbered. The old number was 887. It should be the blue house on the left past the fire hydrant." | Problem solving |
| **Customer call** | Needs to contact customer | "Call the customer for this delivery." Claude initiates the call through CarPlay without Priya touching her phone. | Phone integration |
| **Break time** | Needs food quickly | "Find me a drive-through within 5 minutes that won't take me off route." Claude finds options and estimates wait times. | Route-aware search |
| **Shift end** | Completing last delivery | Claude: "All 42 packages delivered. Total drive time: 6 hours 23 minutes. 3 packages had delivery notes. Want me to save today's route stats?" | Session summary |

### Key Outcomes
- Efficiency: 15-20% fewer miles through optimized routing
- Zero phone handling: complete hands-free operation
- Institutional memory: gate codes, delivery preferences recalled across shifts

---

## Journey 4: The Parent on School Run

**Persona**: David, 38, father of two (ages 6 and 9), manages morning school drop-off and after-school activities.

### Context
David handles a complex daily schedule of school drop-offs, pickups, sports practice, and errands — often with kids in the car generating noise and distraction.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Morning rush** | Loading kids, running late | "Are we late for school?" Claude: "School starts at 8:15. It's 7:52 and the drive is 18 minutes. You'll be about 5 minutes late. Want me to notify the school office?" | Time-aware |
| **Kid question** | 6-year-old asks something | "Why is the sky blue?" Claude gives a kid-friendly explanation: "Great question! The sky looks blue because sunlight bounces off tiny bits in the air, and blue light bounces the most!" | Family mode |
| **Schedule management** | Remembering afternoon plans | "What are the kids' activities today?" Claude: "Emma has soccer at 4 PM at Riverside Park. Jake has piano at 4:30 on Main Street. You'll need to split pickup — want me to text your partner?" | Calendar + messaging |
| **Safety interaction** | Driving in school zone | Claude automatically reduces response verbosity and speaks more quietly near school zones (detected via GPS + speed). | Safety adaptation |
| **Grocery stop** | Quick errand between pickups | "Add milk and bananas to the grocery list and find the nearest store on my route." Claude updates the shared family list and navigates. | List + navigation |
| **Emergency** | Kid feels sick at school | School calls via CarPlay. After the call, David: "Navigate to school, then find the nearest urgent care." Claude chains the destinations. | Multi-stop navigation |

### Key Outcomes
- Reduced stress: schedule management without mental overhead
- Safety: minimal distraction interface, automatic school-zone adaptation
- Family coordination: shared lists, partner messaging, schedule awareness

---

## Journey 5: The Sales Representative

**Persona**: Lisa, 46, pharmaceutical sales rep, visits 6-8 medical offices per day across a metro area.

### Context
Lisa spends 4-5 hours driving between client meetings. Her car is her mobile office — she needs CRM updates, meeting prep, and call management.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Morning briefing** | Starting the day's route | "Brief me on today's visits." Claude reads from synced calendar: "You have 7 visits today. First is Dr. Patel at 9 AM — last visit was 3 weeks ago, she was interested in the new cardiac line." | CRM context |
| **Meeting prep** | Driving to next appointment | "What should I know about Dr. Chen's practice?" Claude: "Internal medicine, 4 providers, currently using competitor product X. Your proposal from last month is pending. Key concern was pricing." | Pre-call prep |
| **Post-meeting notes** | Leaving an appointment | "Note for Dr. Patel: interested in samples, follow up in two weeks, prefers email." Claude logs the note with timestamp and location. | Voice CRM entry |
| **Rescheduling** | Client cancels | "Dr. Chen cancelled the 2 PM. Who else is nearby that I haven't visited in over a month?" Claude cross-references location, CRM data, and visit history. | Intelligent routing |
| **Conference call** | Joining team standup | "Join my 3 PM call." Claude connects through CarPlay, mutes for the first few minutes of updates, then: "You're up next, want me to unmute?" | Call management |
| **End of day report** | Driving home | "Summarize today." Claude: "7 visits completed, 2 rescheduled. 3 follow-ups needed this week. You drove 127 miles. Expense report draft is ready." | Daily summary |

### Key Outcomes
- Productivity: meeting prep and CRM notes without stopping
- Revenue: intelligent rescheduling fills gaps from cancellations
- Compliance: accurate visit logging for regulatory requirements

---

## Journey 6: The Elderly Driver

**Persona**: Robert, 72, retired teacher, drives locally for groceries, doctor appointments, and social activities.

### Context
Robert is comfortable driving familiar routes but gets anxious in unfamiliar areas. He appreciates clear, simple instructions and a patient assistant.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Departure** | Going to new doctor's office | "Take me to Dr. Wilson's office on Magnolia Drive." Claude: "I found Dr. Wilson at 340 Magnolia Drive. It's about 20 minutes away. I'll guide you step by step." | Clear, simple voice |
| **Navigation anxiety** | Approaching complex intersection | Claude gives extra-early guidance: "In about half a mile, you'll want the right lane. The turn is right after the Walgreens on the corner." Uses landmarks, not just distances. | Landmark-based nav |
| **Confusion** | Missed a turn | "I think I went the wrong way." Claude calmly: "No problem at all. Just keep going straight and I'll find you a new route. You're doing fine." | Reassuring tone |
| **Parking** | Arriving at destination | Claude: "The parking lot entrance is on your right, just past the building. There's usually spots near the back entrance." | Arrival assistance |
| **Emergency** | Feeling unwell while driving | "I don't feel well." Claude: "I'm going to help you. Can you pull over safely? There's a parking lot coming up on your right in 200 feet. I can call 911 or your emergency contact, Margaret." | Emergency protocol |
| **Medication reminder** | After doctor visit | Claude: "Reminder — Dr. Wilson said to take the new prescription with dinner tonight. Want me to set an evening reminder?" | Health integration |

### Key Outcomes
- Confidence: patient, landmark-based navigation reduces anxiety
- Safety: emergency protocols with pre-configured contacts
- Independence: technology that enables rather than intimidates

---

## Journey 7: The Rideshare Driver

**Persona**: Carlos, 27, part-time Uber driver, drives 20-25 hours/week evenings and weekends.

### Context
Carlos drives for income while finishing a graduate degree. He needs to maximize earnings per hour, manage passenger interactions, and stay safe during late-night shifts.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Shift start** | Going online | "Where should I position for rides tonight?" Claude: "Based on historical patterns, the downtown bar district will surge around 11 PM. Position near 5th and Main by 10:45. Currently, the airport has a 15-minute queue." | Demand prediction |
| **Passenger pickup** | Approaching pickup location | Claude: "Your rider Jordan is at the corner of 8th and Vine, blue jacket. Rating 4.9. It's a 22-minute ride to Buckhead." | Ride context |
| **Small talk** | Passenger asks about area | Claude (to Carlos through discreet earpiece): "The building on your left is the Fox Theatre, opened in 1929, one of the last remaining movie palaces." | Driver assist mode |
| **Safety concern** | Late night, unfamiliar area | Claude monitors: "This destination is in a low-rated area for drivers. I'll keep tracking your location. Say 'help' at any time to alert your emergency contact." | Safety monitoring |
| **Earnings optimization** | Between rides | "How am I doing tonight?" Claude: "You've earned $87 in 3.5 hours — $24.86/hour. Surge pricing is active in Midtown right now, 8 minutes away." | Earnings tracking |
| **Shift end** | Getting tired | Claude: "You've been driving for 5 hours. Your reaction time may be affected. Based on current demand, one more surge ride could add ~$25, or you could call it a responsible night." | Fatigue awareness |

### Key Outcomes
- Earnings optimization: positioning and surge awareness
- Safety: monitoring, emergency protocols, fatigue alerts
- Professionalism: contextual knowledge for passenger interactions

---

## Journey 8: The Weekend Explorer

**Persona**: Aisha, 31, urban professional, uses weekends to explore new restaurants, hiking trails, and neighborhoods.

### Context
Aisha treats driving as part of the experience. She wants an assistant that helps her discover new places, shares interesting context, and adapts to spontaneous plans.

### Touchpoints

| Stage | Action | Claude Interaction | Channel |
|---|---|---|---|
| **Saturday morning** | No specific plans | "Surprise me with something fun within an hour's drive." Claude: "There's a farmers market in Decatur that's highly rated and only 25 minutes away. Or, the Chattahoochee trail has perfect weather for a hike today — 68 degrees and sunny." | Discovery mode |
| **En route to trail** | Curious about area | "What's the history of this neighborhood?" Claude shares local stories, points out architectural details, mentions upcoming community events. | Contextual storytelling |
| **Trailhead** | Parking and prep | Claude: "Parking is free at the main lot. The moderate loop is 4.2 miles, about 2 hours. There's no cell service on the eastern section — I'll cache what you might need." | Pre-activity prep |
| **Post-hike** | Hungry | "Find me the best tacos nearby that aren't a chain." Claude filters by rating, distance, and type: "Taqueria El Sol is 12 minutes away — 4.7 stars, 800 reviews, known for their birria tacos." | Curated recommendations |
| **Restaurant** | Waiting for food | (Parked, full display mode) Claude shows: "While you're here — there's a free jazz concert in Piedmont Park tonight at 7 PM, and a popup bookshop two blocks from here." | Extended engagement |
| **Evening** | Heading home satisfied | Claude: "Great day — you hiked 4.2 miles and discovered 2 new spots. Want me to save Taqueria El Sol to your favorites?" | Session memory |
| **Following week** | Planning next weekend | "What was that taco place from last Saturday?" Claude: "Taqueria El Sol in East Point. You rated it highly. Want to go again, or try something new in that area?" | Long-term recall |

### Key Outcomes
- Discovery: AI-curated experiences beyond algorithm-driven recommendations
- Spontaneity: supports unplanned adventures with real-time suggestions
- Personal memory: builds a history of preferences and favorites

---

## Cross-Journey Design Principles

1. **Voice-first, always**: Every interaction must be completable without touching the screen.
2. **Context over commands**: Claude should infer intent from situation, not require precise phrasing.
3. **Safety-adaptive**: Response length, volume, and proactivity adjust to driving conditions.
4. **Graceful degradation**: Offline mode preserves core functionality without connectivity.
5. **Personality consistency**: Claude's tone is helpful, warm, and never condescending — regardless of user segment.
6. **Progressive disclosure**: Simple answers first, detail on request ("Want to know more?").
7. **Privacy respect**: Location and conversation data stays on-device unless explicitly shared.
8. **Session memory**: Claude remembers within a trip and across trips, building a useful personal context.
