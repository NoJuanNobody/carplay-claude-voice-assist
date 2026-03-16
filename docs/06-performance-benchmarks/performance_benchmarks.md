# Performance Benchmarks

## Overview

This document defines the performance targets, measurement methodology, and monitoring strategy for the CarPlay Claude Voice Assistant. Every benchmark has a clear target, a measurement approach, and an alerting threshold that triggers investigation when breached.

The primary performance goal is an end-to-end latency of under 3 seconds from the moment the user finishes speaking to the moment audio playback of the response begins. This target applies at the P95 level under normal network conditions (LTE or better).

---

## 1. Latency Targets

### 1.1 End-to-End Latency Budget

The total voice-to-response pipeline is budgeted as follows:

```
User finishes speaking
    |
    +-- [Voice Activity Detection]  ~50ms
    |
    +-- [STT Processing]            ≤ 500ms (P95)
    |
    +-- [PII Scrubbing]             ≤ 20ms
    |
    +-- [Claude API Request]        ≤ 2,000ms (P95)
    |       (includes network RTT + model inference)
    |
    +-- [Response Post-processing]  ≤ 30ms
    |       (safety gate, truncation)
    |
    +-- [TTS Synthesis]             ≤ 300ms (P95)
    |
    +-- [Audio Playback Start]      ≤ 50ms
    |
    = Total                         ≤ 2,950ms (P95 budget)
                                    Target: < 3,000ms P95
```

### 1.2 Component-Level Targets

| Component | P50 Target | P95 Target | P99 Target | Timeout |
|---|---|---|---|---|
| Voice Activity Detection (VAD) | 30ms | 50ms | 100ms | 200ms |
| Speech-to-Text (on-device) | 200ms | 500ms | 800ms | 2,000ms |
| PII Scrubbing Pipeline | 5ms | 20ms | 50ms | 100ms |
| Claude API (network + inference) | 800ms | 2,000ms | 3,500ms | 8,000ms |
| Response Post-processing | 10ms | 30ms | 50ms | 100ms |
| Text-to-Speech Synthesis | 100ms | 300ms | 500ms | 1,000ms |
| Audio Route Setup | 20ms | 50ms | 100ms | 500ms |

### 1.3 Streaming Latency (Time to First Token)

For Claude API responses, we use streaming to begin TTS synthesis before the full response is received:

| Metric | Target |
|---|---|
| Time to first API token | < 400ms P95 |
| Time to first spoken word | < 1,200ms P95 (VAD + STT + network + first token + TTS of first segment) |
| Inter-chunk TTS gap | < 50ms (seamless speech) |

This streaming approach reduces perceived latency by approximately 40% compared to waiting for the full response.

### 1.4 STT Performance Detail

On-device speech recognition using `SFSpeechRecognizer`:

| Metric | Target | Measurement |
|---|---|---|
| Recognition accuracy (en-US) | > 95% word accuracy | Tested against standard speech corpus |
| Recognition accuracy (noisy car) | > 88% word accuracy | Tested with 70dB road noise background |
| Partial result latency | < 100ms from speech | Time from phoneme to partial result callback |
| Final result latency | < 500ms from end of speech | Time from speech end to final transcript |
| Memory usage during recognition | < 30MB incremental | Measured via Instruments |

---

## 2. Memory Budget

### 2.1 CarPlay Extension Memory Limits

The CarPlay UI extension operates under strict memory constraints enforced by iOS. Exceeding the limit results in the extension being terminated by the system (`SIGKILL`).

| Component | Budget | Measurement |
|---|---|---|
| **Total CarPlay extension** | **< 50MB** | Instruments > Allocations |
| UI layer (CPTemplates + rendering) | < 10MB | Template instance tracking |
| Audio engine (AVAudioEngine) | < 8MB | Audio buffer pool monitoring |
| STT engine (SFSpeechRecognizer) | < 15MB | Peak during active recognition |
| TTS engine (AVSpeechSynthesizer) | < 5MB | Peak during synthesis |
| Conversation context cache | < 5MB | Serialized context window size |
| Networking stack | < 3MB | URLSession + response buffers |
| Overhead (runtime, stack, etc.) | < 4MB | Remaining allocation |

### 2.2 Host App Memory Budget

The main iPhone app (background process supporting the CarPlay extension):

| Component | Budget | Notes |
|---|---|---|
| **Total host app** | **< 100MB** | Background process; iOS may terminate if exceeding |
| CoreData store (in-memory cache) | < 20MB | Conversation history, settings |
| Response cache (NSURLCache) | < 30MB | Disk-backed, memory-mapped |
| PII scrubbing models | < 15MB | NLTagger + regex engines |
| Background task coordination | < 5MB | BGAppRefreshTask management |
| Remaining overhead | < 30MB | Runtime, frameworks |

### 2.3 Memory Leak Detection

Automated memory leak detection runs in CI:

```swift
// XCTest memory measurement
func testAssistantSessionDoesNotLeak() {
    let tracker = MemoryLeakTracker()

    autoreleasepool {
        let session = AssistantSession()
        tracker.track(session)
        session.processQuery("What's the weather?")
        session.tearDown()
    }

    XCTAssertTrue(tracker.allObjectsDeallocated,
                  "AssistantSession leaked: \(tracker.leakedObjects)")
}
```

Additionally, every nightly CI run includes:
- Instruments Leaks template execution against a 30-minute simulated session
- Peak memory watermark tracking (alert if > 45MB in CarPlay extension)
- Memory growth rate analysis (alert if > 1MB/minute sustained growth)

---

## 3. Battery Impact

### 3.1 Target

**< 5% battery drain per hour of active use** on iPhone 14 or newer.

### 3.2 Power Budget Breakdown

| Component | Power Draw | Duty Cycle | Contribution |
|---|---|---|---|
| Microphone (AVAudioEngine) | ~50mW | 100% during active listening | ~30% of total |
| STT (SFSpeechRecognizer, Neural Engine) | ~200mW | ~10% (only during speech) | ~15% of total |
| Networking (LTE radio) | ~500mW | ~5% (API request bursts) | ~20% of total |
| TTS (AVSpeechSynthesizer) | ~100mW | ~8% (response playback) | ~10% of total |
| Display (CarPlay, managed by head unit) | 0mW (external) | N/A | 0% |
| CPU (main thread, coordination) | ~100mW | 100% (lightweight) | ~15% of total |
| Idle baseline (between queries) | ~30mW | ~70% of session time | ~10% of total |

### 3.3 Power Optimization Strategies

1. **Aggressive VAD gating:** The audio engine captures continuously, but STT is only activated when voice activity is detected, reducing Neural Engine usage by ~90%
2. **Streaming chunked TTS:** TTS synthesis begins with the first response chunk, avoiding a burst of CPU activity at the end
3. **Connection keep-alive:** Reuse HTTP/2 connections to the Claude API to avoid repeated TLS handshakes (each handshake costs ~100ms of radio time)
4. **Batch analytics:** Queue analytics events and send in a single burst every 5 minutes rather than per-event
5. **Adaptive audio quality:** Use 16kHz mono for STT input (sufficient for speech recognition) rather than 44.1kHz stereo

### 3.4 Battery Measurement Protocol

Battery impact is measured under controlled conditions:

- **Device:** iPhone 14 Pro, battery health > 95%
- **Starting charge:** 100%
- **Test scenario:** 1 hour of mixed queries (10 queries/hour, varying complexity)
- **Network:** Simulated LTE (controlled RF environment)
- **CarPlay:** Connected to CarPlay simulator (USB)
- **Baseline:** Same scenario with the app not installed (to isolate app contribution)
- **Measurement tool:** Instruments > Energy Log, `IOReportCopyAllChannels`

---

## 4. Network Performance

### 4.1 Bandwidth Requirements

| Network Condition | Behavior | Quality Level |
|---|---|---|
| **5G / Wi-Fi** | Full functionality, fastest responses | Premium |
| **LTE (4G)** | Full functionality, target latencies met | Full |
| **3G** | Graceful degradation: shorter context window, cached responses preferred | Degraded |
| **2G / EDGE** | Offline mode with pre-cached responses only | Minimal |
| **No connectivity** | Offline mode: pre-cached responses, on-device FAQ | Offline |

### 4.2 Request Payload Sizes

| Direction | Typical Size | Maximum Size | Compression |
|---|---|---|---|
| Request (user query + context) | 2-4 KB | 16 KB | gzip (Content-Encoding) |
| Response (Claude text) | 0.5-2 KB | 8 KB | gzip (Accept-Encoding) |
| Streaming chunk | 50-200 bytes | 500 bytes | None (chunked transfer) |

### 4.3 Graceful Degradation on 3G

When the network is detected as 3G or slower (via `NWPathMonitor` and RTT measurement):

1. **Reduce context window:** Send only the current query (no conversation history) to minimize request size
2. **Prefer cached responses:** Check local cache before making API request
3. **Extend timeout:** Increase API timeout from 8s to 15s
4. **Simplify responses:** Add system prompt instruction to keep responses under 50 tokens
5. **Disable streaming:** Use standard request/response (streaming overhead is proportionally larger on slow networks)
6. **Queue non-urgent requests:** Batch follow-up queries and send when connectivity improves

```swift
class NetworkAdaptiveStrategy {
    func currentStrategy(path: NWPath) -> RequestStrategy {
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.cellular) {
            let rtt = latencyProbe.lastMeasuredRTT
            if rtt < 100 { return .full }           // LTE+
            if rtt < 500 { return .degraded }        // 3G
            if rtt < 2000 { return .minimal }        // 2G
        }
        return .offline
    }
}
```

### 4.4 Offline Response Capabilities

When no network is available, the assistant can still respond to a curated set of queries using on-device data:

| Category | Examples | Response Source |
|---|---|---|
| Device controls | "Turn up the volume", "Next track" | Direct CarPlay API call |
| Basic math | "What's 15% of 80?" | On-device calculation |
| Time/date | "What time is it?", "What day is today?" | System clock |
| Canned responses | "Tell me a joke", "Good morning" | Pre-loaded response database |
| Last cached query | Repeat of recent query | Local response cache |

**Offline response latency target: < 500ms** (no network round-trip involved).

---

## 5. Cold Start Performance

### 5.1 Targets

| Metric | Target | Measurement Point |
|---|---|---|
| App launch to ready state | < 2.0s | First frame rendered + audio engine ready |
| CarPlay template displayed | < 1.0s | `CPTemplateApplicationScene` `didConnect` to template push |
| Audio engine initialized | < 500ms | `AVAudioEngine.start()` completes |
| STT engine loaded | < 800ms | `SFSpeechRecognizer` ready for input |
| First query processable | < 2.0s | All components initialized, listening active |

### 5.2 Launch Sequence Optimization

```
T+0ms     Process start
T+50ms    Dylib loading complete (minimize dynamic frameworks)
T+100ms   UIApplication/CPApplication initialized
T+150ms   CarPlay scene connected, push initial template
T+200ms   Begin parallel initialization:
            - AVAudioEngine setup (async)
            - SFSpeechRecognizer load (async)
            - CoreData stack init (async)
            - Network session creation (async)
T+500ms   CarPlay template visible to user
T+800ms   Audio engine ready, listening indicator shown
T+1200ms  STT engine ready
T+1500ms  All systems initialized
T+2000ms  Maximum acceptable ready time (with margin)
```

### 5.3 Cold Start Optimization Techniques

1. **Minimize linked frameworks:** Only link frameworks that are used at launch; lazy-load others
2. **Pre-warm in background:** Use `BGAppRefreshTask` to keep the app warm when CarPlay is likely to connect
3. **Parallel initialization:** All independent subsystems initialize concurrently on dedicated dispatch queues
4. **Lazy model loading:** NLP models for PII scrubbing load after first query, not at launch
5. **Pre-compiled templates:** CarPlay UI templates are pre-built and cached, not constructed at launch time
6. **Static dispatch:** Prefer structs and static dispatch over dynamic dispatch in hot paths

---

## 6. Cache Performance

### 6.1 Cache Architecture

```
[L1: In-Memory LRU Cache]     Hit rate target: > 90%
    |                           Capacity: 50 entries
    |                           Eviction: LRU, 5-minute TTL
    |
[L2: Disk Cache (NSURLCache)]  Hit rate target: > 70%
    |                           Capacity: 30MB
    |                           Eviction: LRU, 7-day TTL
    |
[L3: Network (Claude API)]     Fallback when cache misses
```

### 6.2 Cache Hit Rate Targets

| Cache Level | Target Hit Rate | Measurement |
|---|---|---|
| L1 (in-memory) | > 90% for repeated queries within 5 minutes | Counter in CacheManager |
| L2 (disk) | > 70% for queries seen within 7 days | NSURLCache statistics |
| Combined (L1 + L2) | > 80% across all queries | Composite metric |

### 6.3 Cache Key Strategy

Cache keys are generated from the normalized, PII-scrubbed query text:

```swift
struct CacheKeyGenerator {
    static func key(for query: String, context: ConversationContext?) -> String {
        let normalized = query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        // Context-sensitive cache: same query with different context = different key
        let contextHash = context?.lastTurnHash ?? "no-context"
        let composite = "\(normalized)|ctx:\(contextHash)"

        return SHA256.hash(data: composite.data(using: .utf8)!)
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
```

### 6.4 Cache Invalidation

- **Time-based:** L1 entries expire after 5 minutes; L2 entries expire after 7 days
- **Content-based:** Queries about time-sensitive topics (weather, scores, traffic) bypass cache entirely
- **Manual:** User can clear cache via Settings > Storage > Clear Cache
- **Capacity-based:** LRU eviction when capacity limits are reached

---

## 7. Concurrent Session Handling

### 7.1 Session Model

The assistant supports one active session per CarPlay connection. However, the following concurrent scenarios must be handled:

| Scenario | Behavior | Priority |
|---|---|---|
| User query during TTS playback | Interrupt TTS, process new query | New query wins |
| API response arrives during new query | Discard stale response, process new query | New query wins |
| Phone call during assistant session | Pause assistant, resume after call | Phone call wins |
| Siri activation during assistant session | Pause assistant, resume after Siri | Siri wins |
| Multiple rapid queries (< 1s apart) | Process only the last query (debounce) | Last query wins |
| Background app refresh during session | Defer refresh until session idle | Active session wins |

### 7.2 Request Cancellation

When a new query supersedes an in-flight request:

```swift
class RequestManager {
    private var currentTask: URLSessionDataTask?

    func sendQuery(_ query: String) async throws -> String {
        // Cancel any in-flight request
        currentTask?.cancel()

        let task = session.dataTask(with: buildRequest(query))
        currentTask = task

        return try await withCheckedThrowingContinuation { continuation in
            task.completionHandler = { data, response, error in
                if let error = error as? URLError, error.code == .cancelled {
                    // Silently discard cancelled requests
                    return
                }
                // Process response...
            }
            task.resume()
        }
    }
}
```

### 7.3 Resource Contention

| Resource | Concurrency Limit | Contention Strategy |
|---|---|---|
| AVAudioEngine | 1 instance | Shared; STT and TTS alternate |
| SFSpeechRecognizer | 1 active recognition task | Cancel previous, start new |
| URLSession | 4 concurrent connections (HTTP/2 multiplexed) | Queue excess requests |
| CoreData context | 1 writer, N readers | Write serialization via performAndWait |

---

## 8. Load Testing Methodology

### 8.1 Test Scenarios

| Test | Description | Duration | Query Rate |
|---|---|---|---|
| **Steady state** | Normal usage pattern | 1 hour | 10 queries/hour |
| **Burst** | Rapid sequential queries | 5 minutes | 1 query/5 seconds |
| **Endurance** | Extended session | 8 hours | 5 queries/hour |
| **Network degradation** | Simulated 3G with packet loss | 30 minutes | 10 queries/hour |
| **Memory stress** | Large context windows, long responses | 1 hour | 20 queries/hour |
| **Cold start spam** | Repeated CarPlay connect/disconnect | 30 minutes | 1 reconnect/minute |

### 8.2 Test Infrastructure

```
[Test Harness (macOS)]
    |
    +-- XCUITest driver (simulates user speech via audio injection)
    |
    +-- CarPlay Simulator (Xcode)
    |
    +-- Network Link Conditioner (simulates various network conditions)
    |
    +-- Mock Claude API server (deterministic response latencies)
    |
    +-- Instruments recording (CPU, Memory, Energy, Network)
    |
    +-- Custom metrics collector (writes to InfluxDB)
```

### 8.3 Measurement Collection

During load tests, the following metrics are collected at 1-second intervals:

- CPU usage (% of single core)
- Memory (resident set size, virtual size, dirty pages)
- Network (bytes sent/received, connection count, RTT)
- Audio (buffer underruns, latency, sample rate)
- Battery (instantaneous power draw via Energy Instruments)
- Custom counters (cache hits, safety gate blocks, state transitions)

### 8.4 Acceptance Criteria

A build passes load testing only if ALL of the following conditions are met during the endurance test:

- P95 end-to-end latency < 3,000ms
- No memory leak (RSS growth < 5MB over 8 hours)
- Zero audio glitches (buffer underruns = 0)
- Zero crashes or hangs
- Battery impact < 5% per hour (extrapolated from Energy Instruments)
- Cache hit rate > 80% for repeated queries

---

## 9. Monitoring and Alerting Thresholds

### 9.1 Real-Time Monitoring (Production)

All metrics are collected on-device and, if the user has opted into analytics, reported in anonymized, aggregated form.

| Metric | Collection Method | Granularity |
|---|---|---|
| End-to-end latency | `os_signpost` intervals | Per-query |
| Component latencies | `os_signpost` intervals | Per-component |
| Memory RSS | `task_info` | Every 30 seconds |
| Cache hit rate | Counter in CacheManager | Per-query |
| API error rate | HTTP status code tracking | Per-request |
| STT accuracy estimate | Confidence score from SFSpeechRecognizer | Per-query |
| Safety gate activations | Counter in SafetyGate | Per-action |

### 9.2 Alerting Thresholds

| Metric | Warning Threshold | Critical Threshold | Action |
|---|---|---|---|
| P95 latency | > 3,000ms (5min window) | > 5,000ms (5min window) | Page on-call; investigate API/network |
| Memory RSS | > 45MB (CarPlay ext) | > 48MB (CarPlay ext) | Force cache eviction; log diagnostics |
| API error rate | > 5% (5min window) | > 20% (5min window) | Switch to cached/offline mode |
| Cache hit rate | < 70% (1hr window) | < 50% (1hr window) | Investigate cache invalidation issues |
| STT confidence | < 80% average (1hr) | < 60% average (1hr) | Log audio quality metrics for analysis |
| Crash rate | > 0.1% sessions | > 1% sessions | Halt rollout; investigate |
| Cold start time | > 2,500ms P95 | > 4,000ms P95 | Profile launch sequence |

### 9.3 On-Device Diagnostics

When a critical threshold is breached, the system automatically captures a diagnostic snapshot:

```swift
struct DiagnosticSnapshot {
    let timestamp: Date
    let triggerMetric: String
    let triggerValue: Double
    let memoryRSS: UInt64
    let cpuUsage: Double
    let activeThreadCount: Int
    let cacheEntryCount: Int
    let networkCondition: NetworkCondition
    let drivingState: DrivingState
    let recentLatencies: [TimeInterval]  // Last 10 queries
}
```

Snapshots are stored on-device (max 100, FIFO eviction) and included in diagnostic reports if the user explicitly submits a bug report.

### 9.4 Performance Regression Detection (CI/CD)

Every PR runs a performance test suite that compares against the baseline:

| Check | Regression Threshold | Action |
|---|---|---|
| P95 latency increase | > 10% vs. baseline | Block merge; require investigation |
| Memory peak increase | > 5MB vs. baseline | Block merge; require investigation |
| Cold start regression | > 200ms vs. baseline | Warning; review optional |
| Binary size increase | > 1MB vs. baseline | Warning; review optional |
| Framework count change | Any new dynamic framework | Block merge; require justification |

Baselines are updated from the `main` branch nightly. Performance tests run on dedicated CI hardware (Mac Mini M2, iPhone 15 Pro connected via USB) to ensure consistent measurement conditions.

---

## 10. Performance Optimization Roadmap

### 10.1 Current State vs. Targets

| Metric | Current (Estimated) | Target | Gap |
|---|---|---|---|
| E2E latency (P95) | ~3,500ms | < 3,000ms | 500ms to close |
| STT latency | ~400ms | < 500ms | On target |
| API latency (P95) | ~2,500ms | < 2,000ms | 500ms to close |
| TTS latency | ~250ms | < 300ms | On target |
| Memory (CarPlay ext) | ~40MB | < 50MB | 10MB headroom |
| Cold start | ~1,800ms | < 2,000ms | On target |
| Battery impact | ~6%/hr | < 5%/hr | 1% to close |

### 10.2 Planned Optimizations

1. **Speculative prefetch:** Begin API request with partial transcript while STT is still processing (saves ~200ms)
2. **Response caching with semantic similarity:** Cache responses and match queries by embedding similarity, not exact match (improves hit rate by ~15%)
3. **TTS pre-synthesis:** Pre-synthesize common response prefixes ("Sure,", "The weather is", etc.) and splice with dynamic content
4. **HTTP/3 (QUIC):** Reduce connection setup latency by ~100ms on new connections
5. **Model distillation:** Work with Anthropic on a smaller, faster model variant for simple queries (target: < 500ms API latency for simple factual queries)
6. **Adaptive context window:** Dynamically size the context window based on network speed and query complexity
