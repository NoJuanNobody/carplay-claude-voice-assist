# Traceability Matrix

This document maps all functional and non-functional requirements to their implementation and test files.

## Functional Requirements

| Req ID | Requirement | Implementation File(s) | Test File(s) | Status |
|--------|-------------|----------------------|-------------|--------|
| FR-01 | Voice capture and STT | `ios/.../Voice/VoiceCaptureEngine.swift`, `ios/.../Voice/SpeechRecognizer.swift` | `ios/.../Tests/CarPlayAssistantTests/VoicePipelineTests.swift` | Implemented |
| FR-02 | Text-to-speech response | `ios/.../Voice/TextToSpeech.swift` | `ios/.../Tests/CarPlayAssistantTests/VoicePipelineTests.swift` | Implemented |
| FR-03 | Claude AI conversation | `backend/app/services/claude_client.rb`, `backend/app/services/context_manager.rb` | `backend/spec/services/claude_client_spec.rb`, `backend/spec/services/context_manager_spec.rb`, `backend/spec/integration/full_conversation_flow_spec.rb` | Implemented |
| FR-04 | Multi-turn context | `backend/app/services/context_manager.rb`, `ios/.../Context/SessionManager.swift` | `backend/spec/services/context_manager_spec.rb`, `backend/spec/integration/full_conversation_flow_spec.rb` | Implemented |
| FR-05 | Vehicle state awareness | `backend/app/services/vehicle_context_service.rb`, `ios/.../Context/VehicleStateProvider.swift` | `backend/spec/services/vehicle_context_service_spec.rb` | Implemented |
| FR-06 | Navigation integration | `backend/app/services/integrations/maps_adapter.rb` | `backend/spec/services/integrations/maps_adapter_spec.rb`, `backend/spec/integration/full_conversation_flow_spec.rb` | Implemented |
| FR-07 | Calendar integration | `backend/app/services/integrations/calendar_adapter.rb` | (unit tests pending) | Implemented |
| FR-08 | Messages integration | `backend/app/services/integrations/messages_adapter.rb` | `backend/spec/services/integrations/messages_adapter_spec.rb` | Implemented |
| FR-09 | Music playback | `backend/app/services/integrations/media_adapter.rb` | (unit tests pending) | Implemented |
| FR-10 | Weather queries | `backend/app/services/integrations/weather_adapter.rb` | (unit tests pending) | Implemented |
| FR-11 | User profiles | `backend/app/services/profile_service.rb`, `ios/.../Profile/UserProfile.swift` | `backend/spec/services/profile_service_spec.rb` | Implemented |
| FR-12 | Voice signatures | `backend/app/services/voice_signature_service.rb`, `ios/.../Voice/VoiceCaptureEngine.swift` | `backend/spec/services/voice_signature_service_spec.rb` | Implemented |
| FR-13 | Offline fallback | `backend/app/services/offline/fallback_response_service.rb`, `ios/.../Offline/LocalResponseEngine.swift` | `backend/spec/services/offline/fallback_response_service_spec.rb`, `backend/spec/integration/offline_flow_spec.rb`, `ios/.../Tests/CarPlayAssistantTests/OfflineTests.swift` | Implemented |
| FR-14 | Emergency handling | `backend/app/services/safety/emergency_handler.rb`, `ios/.../Safety/EmergencyProtocol.swift` | `backend/spec/services/safety/emergency_handler_spec.rb`, `backend/spec/integration/safety_flow_spec.rb`, `ios/.../Tests/CarPlayAssistantTests/SafetyTests.swift` | Implemented |
| FR-15 | Safety enforcement | `backend/app/services/safety/response_validator.rb`, `ios/.../Safety/UIComplianceEngine.swift` | `backend/spec/services/safety/response_validator_spec.rb`, `backend/spec/integration/safety_flow_spec.rb`, `ios/.../Tests/CarPlayAssistantTests/SafetyTests.swift` | Implemented |

## Non-Functional Requirements

| Req ID | Requirement | Implementation File(s) | Test File(s) | Status |
|--------|-------------|----------------------|-------------|--------|
| NFR-01 | Latency < 3s P95 | `backend/lib/metrics/collector.rb`, `backend/lib/metrics/request_middleware.rb` | `backend/spec/lib/metrics/collector_spec.rb`, `backend/spec/lib/metrics/request_middleware_spec.rb` | Implemented |
| NFR-02 | Privacy (audio on-device) | `ios/.../Voice/VoicePipeline.swift`, `ios/.../Voice/PCCClient.swift` | `ios/.../Tests/CarPlayAssistantTests/VoicePipelineTests.swift` | Implemented |
| NFR-03 | Memory < 50MB | `ios/.../Offline/OfflineCacheManager.swift` (50MB limit constant) | `ios/.../Tests/CarPlayAssistantTests/OfflineTests.swift` | Implemented |
| NFR-04 | Offline response < 500ms | `ios/.../Offline/LocalResponseEngine.swift` | `ios/.../Tests/CarPlayAssistantTests/OfflineTests.swift` | Implemented |
| NFR-05 | Cache hit rate > 80% | `backend/app/services/cache_service.rb` | `backend/spec/services/cache_service_spec.rb` | Implemented |
| NFR-06 | Health monitoring | `backend/app/services/health_check_service.rb`, `backend/app/controllers/api/v1/health_controller.rb` | `backend/spec/services/health_check_service_spec.rb`, `backend/spec/requests/api/v1/health_spec.rb` | Implemented |
| NFR-07 | Data retention policies | `docs/05-privacy-framework/` | (policy document, no code tests) | Documented |
| NFR-08 | CarPlay HIG compliance | `ios/.../Safety/UIComplianceEngine.swift` | `ios/.../Tests/CarPlayAssistantTests/SafetyTests.swift` | Implemented |

## Integration Test Coverage

| Test Suite | File | Requirements Covered |
|-----------|------|---------------------|
| Full Conversation Flow | `backend/spec/integration/full_conversation_flow_spec.rb` | FR-03, FR-04, FR-06, NFR-01 |
| Safety Flow | `backend/spec/integration/safety_flow_spec.rb` | FR-14, FR-15 |
| Offline Flow | `backend/spec/integration/offline_flow_spec.rb` | FR-13 |
| Voice Pipeline (Swift) | `ios/.../Tests/CarPlayAssistantTests/VoicePipelineTests.swift` | FR-01, FR-02, NFR-02 |
| Safety (Swift) | `ios/.../Tests/CarPlayAssistantTests/SafetyTests.swift` | FR-15, NFR-08, FR-14 |
| Offline (Swift) | `ios/.../Tests/CarPlayAssistantTests/OfflineTests.swift` | FR-13, NFR-03, NFR-04 |
