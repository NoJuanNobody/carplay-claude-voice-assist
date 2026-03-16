# CarPlay Claude Voice Assistant

A privacy-first CarPlay voice assistant powered by Claude. Audio stays on-device via Apple's Speech framework and Private Cloud Compute — only transcribed text reaches the backend, where Claude handles reasoning, multi-turn conversation, and tool execution.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  iOS Device                                             │
│  ┌───────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Voice Pipeline │  │   Safety     │  │   Offline    │ │
│  │ AVAudioEngine  │  │ DrivingState │  │ LocalEngine  │ │
│  │ SFSpeech (STT) │  │ UICompliance │  │ CacheManager │ │
│  │ AVSpeech (TTS) │  │ Emergency    │  │ NetworkMon   │ │
│  │ PCC Client     │  │              │  │              │ │
│  └───────┬────────┘  └──────────────┘  └──────────────┘ │
│          │ text only                                     │
└──────────┼──────────────────────────────────────────────┘
           │ HTTPS (JWT auth)
┌──────────▼──────────────────────────────────────────────┐
│  Rails API Backend                                       │
│  ┌────────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │ Context Manager │  │  Integration  │  │   Safety    │ │
│  │ Claude Client   │  │  Orchestrator │  │  Middleware  │ │
│  │ Session Mgmt    │  │  6 Adapters   │  │  Validator  │ │
│  └────────┬───────┘  └───────────────┘  └─────────────┘ │
│           │                                              │
│  ┌────────▼───────┐  ┌──────┐  ┌──────────┐            │
│  │  Claude API     │  │Redis │  │PostgreSQL│            │
│  │  (Anthropic)    │  │Cache │  │  8 tables│            │
│  └────────────────┘  └──────┘  └──────────┘            │
└──────────────────────────────────────────────────────────┘
```

**Key principle:** Audio never leaves the device. The backend never sees or stores audio data.

## Project Structure

```
├── backend/                    # Rails 7 API
│   ├── app/
│   │   ├── controllers/api/v1/ # REST endpoints
│   │   ├── models/             # 8 ActiveRecord models
│   │   └── services/
│   │       ├── claude_client.rb         # Anthropic API wrapper
│   │       ├── context_manager.rb       # Session + conversation orchestration
│   │       ├── cache_service.rb         # Redis with namespaced TTLs
│   │       ├── profile_service.rb       # Multi-user profiles
│   │       ├── voice_signature_service.rb
│   │       ├── vehicle_context_service.rb
│   │       ├── health_check_service.rb
│   │       ├── integrations/            # Tool execution adapters
│   │       │   ├── orchestrator.rb
│   │       │   ├── maps_adapter.rb
│   │       │   ├── calendar_adapter.rb
│   │       │   ├── messages_adapter.rb
│   │       │   ├── media_adapter.rb
│   │       │   ├── weather_adapter.rb
│   │       │   └── vehicle_adapter.rb
│   │       ├── safety/                  # Driving safety enforcement
│   │       │   ├── driving_state_evaluator.rb
│   │       │   ├── response_validator.rb
│   │       │   ├── emergency_handler.rb
│   │       │   └── safety_middleware.rb
│   │       └── offline/                 # Fallback responses
│   ├── db/migrate/             # 8 migrations (UUID PKs)
│   ├── lib/metrics/            # Performance monitoring
│   └── spec/                   # RSpec tests
│
├── ios/CarPlayAssistant/       # Swift Package
│   ├── Sources/CarPlayAssistant/
│   │   ├── Voice/              # Audio capture, STT, TTS, PCC
│   │   ├── Safety/             # Driving monitor, HIG compliance, emergency
│   │   ├── Offline/            # Local cache, network monitor, offline engine
│   │   ├── Context/            # Session manager, vehicle state
│   │   └── Profile/            # User profile management
│   ├── Sources/CarPlayUI/      # CarPlay templates
│   └── Tests/
│
├── docs/                       # 11 documentation frameworks
├── docker-compose.yml          # PostgreSQL + Redis + backend
└── Makefile
```

## Getting Started

### Prerequisites

- Ruby >= 3.1
- PostgreSQL 15+
- Redis 7+
- Xcode 15+ (for iOS development)
- Swift 5.9+

### Quick Start with Docker

```bash
# Start PostgreSQL and Redis
docker compose up -d postgres redis

# Set up the backend
cd backend
bundle install
rails db:create db:migrate
rails server
```

Or run everything in Docker:

```bash
docker compose up
```

### iOS

```bash
cd ios/CarPlayAssistant
swift build
swift test    # 82 tests
```

### Using the Makefile

```bash
make setup          # Full setup (backend + iOS)
make backend-test   # Run RSpec
make ios-build      # Build Swift package
make ios-test       # Run Swift tests
make docker-up      # Start Docker services
make docker-down    # Stop Docker services
```

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude API key | (required) |
| `DATABASE_HOST` | PostgreSQL host | `localhost` |
| `DATABASE_USERNAME` | PostgreSQL user | `postgres` |
| `DATABASE_PASSWORD` | PostgreSQL password | `postgres` |
| `REDIS_URL` | Redis connection URL | `redis://localhost:6379/0` |
| `CORS_ORIGINS` | Allowed CORS origins | `*` |
| `JWT_SECRET` | JWT signing secret | Rails secret key base |

## API Endpoints

### Authentication
| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/auth/register` | Create account |
| POST | `/api/v1/auth/login` | Sign in (returns JWT) |
| DELETE | `/api/v1/auth/logout` | Revoke JWT |
| GET | `/api/v1/auth/me` | Current user info |

### Voice Sessions
| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/sessions` | Start voice session |
| DELETE | `/api/v1/sessions/:id` | End session |
| POST | `/api/v1/sessions/:id/messages` | Send message to Claude |
| GET | `/api/v1/sessions/:id/messages` | Conversation history |

### Profile & Vehicles
| Method | Path | Description |
|---|---|---|
| GET/PUT | `/api/v1/profile` | View/update profile |
| POST/DELETE | `/api/v1/profile/voice_signature` | Voice signature enrollment |
| GET/POST | `/api/v1/vehicles` | List/register vehicles |
| PUT | `/api/v1/vehicles/:id/state` | Update vehicle state |

### Safety & Health
| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/safety/report_event` | Report safety event |
| POST | `/api/v1/safety/emergency` | Trigger emergency protocol |
| GET | `/api/v1/health` | Health check (no auth) |
| GET | `/api/v1/health/detailed` | Detailed health (auth required) |

## How It Works

### Conversation Flow

1. **iOS** captures audio via `AVAudioEngine`, transcribes on-device with `SFSpeechRecognizer`
2. Transcribed text is sent to `POST /api/v1/sessions/:id/messages` with driving state
3. **Backend** builds a system prompt with safety rules based on driving state (parked/city/highway/emergency)
4. **Claude** processes the message and may request tool calls (navigation, messages, calendar, etc.)
5. **Integration orchestrator** executes tool calls and returns results to Claude for a natural language response
6. **Safety validator** enforces response length limits and redacts distracting content (URLs, phone numbers while driving)
7. Response is returned to iOS, where `AVSpeechSynthesizer` speaks it aloud

### Safety Rules by Driving State

| State | Max Response | Restrictions |
|---|---|---|
| Parked | Unlimited | None |
| City | 2 sentences | No URLs, no phone numbers, voice-only |
| Highway | 1 sentence | No URLs, no phone numbers, no complex confirmations |
| Emergency | Critical only | Emergency responses only |

### Caching Strategy

| Namespace | TTL | Purpose |
|---|---|---|
| `session` | 30 min | Active voice session data |
| `profile` | 1 hour | User preferences and settings |
| `vehicle` | 5 min | Vehicle state (speed, location) |
| `integration` | 15 min | Integration credentials |
| `health` | 1 min | Service health snapshots |

## Database Schema

8 tables with UUID primary keys:

- **users** — Devise auth with JWT, voice signature data
- **vehicles** — User vehicles with integration config
- **voice_sessions** — Session lifecycle with driving state tracking
- **conversation_messages** — Full conversation history with token/latency metrics
- **user_preferences** — Voice speed, language, verbosity, safety level
- **integration_credentials** — Per-service encrypted tokens
- **safety_events** — Safety incident log with severity levels
- **system_health_snapshots** — Service health over time

## Documentation

| Doc | Topic |
|---|---|
| [Market Assumptions](docs/01-market-assumptions/market_assumptions.md) | TAM/SAM, target demographics, adoption projections |
| [CarPlay SDK Constraints](docs/02-carplay-sdk-constraints/carplay_sdk_constraints.md) | Template types, screen limits, Apple review guidelines |
| [Safety Scenarios](docs/03-safety-scenarios/safety_scenarios.md) | 25+ scenarios with expected behavior per driving state |
| [Claude/Siri Boundaries](docs/04-claude-siri-boundaries/claude_siri_boundaries.md) | Capability matrix, handoff protocol, conflict resolution |
| [Privacy Framework](docs/05-privacy-framework/privacy_framework.md) | Data flow, GDPR/CCPA compliance, encryption, retention |
| [Performance Benchmarks](docs/06-performance-benchmarks/performance_benchmarks.md) | Latency budgets, memory limits, battery targets |
| [Competitive Differentiation](docs/07-competitive-differentiation/competitive_differentiation.md) | vs Siri, Google Assistant, Alexa Auto |
| [User Journeys](docs/08-user-journeys/user_journeys.md) | 8 persona journey maps with touchpoints |
| [Go-to-Market](docs/09-go-to-market/go_to_market.md) | Launch strategy, pricing, distribution, partnerships |
| [Integration Architecture](docs/10-integration-architecture/integration_architecture.md) | System diagrams, API contracts, sequence flows |
| [Traceability Matrix](docs/20-traceability/traceability_matrix.md) | 15 FRs + 8 NFRs mapped to code and tests |

## License

Proprietary. All rights reserved.
