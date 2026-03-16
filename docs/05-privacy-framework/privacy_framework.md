# Privacy Framework

## Overview

The CarPlay Claude Voice Assistant is designed with privacy as a foundational principle, not an afterthought. This document defines the data flow architecture, encryption requirements, compliance posture, and operational procedures that ensure user data is handled with the highest level of care.

The core privacy guarantee: **audio never leaves the device**. All speech-to-text processing occurs on-device using Apple's Speech framework, and only anonymized transcribed text is transmitted to the Claude API backend.

---

## 1. Data Flow Architecture

### 1.1 On-Device Processing (Never Leaves Device)

The following data categories are processed and stored exclusively on the user's iPhone. They are never transmitted to any backend service, analytics platform, or third party.

| Data Type | Storage Location | Encryption | Retention |
|---|---|---|---|
| Raw audio buffers | Memory only (never persisted) | N/A (volatile) | Discarded after STT completes |
| Voice signatures / voiceprint | Keychain (Secure Enclave) | AES-256, hardware-bound | Until user explicitly deletes |
| Driving state telemetry | App sandbox (CoreData) | NSFileProtectionComplete | Current session only |
| CarPlay UI state | Memory only | N/A (volatile) | Current session only |
| STT interim results | Memory only | N/A (volatile) | Discarded after final transcript |
| User preferences | UserDefaults (app group) | NSFileProtectionComplete | Until app uninstall |

### 1.2 Backend Transmission (Anonymized Text Only)

When a user query requires Claude API processing, the following data flow occurs:

```
[iPhone]                                    [Backend]
   |                                            |
   |-- 1. Audio captured via AVAudioEngine      |
   |-- 2. On-device STT (SFSpeechRecognizer)    |
   |-- 3. Transcript anonymized (PII scrubbed)  |
   |-- 4. Anonymized text ----TLS 1.3---------> |
   |                                            |-- 5. Claude API processes text
   |                                            |-- 6. Response generated
   |   <-----------TLS 1.3--- 7. Text response--|
   |-- 8. On-device TTS (AVSpeechSynthesizer)   |
   |-- 9. Audio played via CarPlay audio route   |
   |                                            |
```

**What is transmitted to the backend:**
- Anonymized transcript text (PII stripped)
- Session identifier (opaque UUID, not linkable to user identity)
- Conversation context window (last N turns, configurable, default 5)
- Device locale and language preference (for response localization)
- Request timestamp (for rate limiting and billing)

**What is NOT transmitted:**
- Raw audio in any form
- User name, Apple ID, or any persistent identifier
- Location data (GPS coordinates, addresses)
- Vehicle information (make, model, VIN)
- Contacts, calendar entries, or other personal data
- Driving state or speed information
- Health metrics or biometric data

### 1.3 PII Scrubbing Pipeline

Before any text leaves the device, it passes through a multi-stage PII detection and redaction pipeline:

```swift
// PII scrubbing stages executed sequentially
struct PIIScrubber {
    static let stages: [PIIDetector] = [
        NSDataDetectorStage(types: [.phoneNumber, .address, .link]),
        NameEntityRecognizer(using: .builtIn),    // NLTagger with .nameType
        CreditCardPatternMatcher(),                // Regex-based CC detection
        SSNPatternMatcher(),                       // Regex-based SSN detection
        EmailPatternMatcher(),                     // Regex-based email detection
        CustomEntityBlocklist(source: .userDefined) // User-added sensitive terms
    ]
}
```

Each detected PII entity is replaced with a category placeholder (e.g., `[PHONE_NUMBER]`, `[ADDRESS]`, `[PERSON_NAME]`) so that Claude can still understand the semantic intent without accessing the actual data.

---

## 2. Private Cloud Compute (PCC) Integration Strategy

### 2.1 PCC Architecture

Apple's Private Cloud Compute provides a hardware-attested, stateless compute environment. When available, the assistant routes requests through PCC rather than directly to the public Claude API endpoint.

**PCC routing decision tree:**

1. Is PCC available on this device/OS version? (Requires iOS 18.0+)
2. Is the request eligible for PCC? (Text-only, within size limits)
3. Is PCC latency within acceptable bounds? (< 3s P95 target)
4. Route via PCC; otherwise fall back to direct API with standard encryption

### 2.2 PCC Guarantees Leveraged

- **Stateless processing:** No request data persists after response is returned
- **Hardware attestation:** Cryptographic proof that server code matches published binary
- **No operator access:** Apple cannot inspect request/response payloads
- **Audit log transparency:** Independent researchers can verify server behavior

### 2.3 Fallback Behavior

When PCC is unavailable, requests are sent directly to the Claude API endpoint over TLS 1.3 with certificate pinning. The same PII scrubbing pipeline applies regardless of routing path. Users are not notified of routing changes to avoid cognitive load while driving.

---

## 3. Data Retention Policies

### 3.1 Retention Schedule

| Data Category | Retention Period | Deletion Trigger | Storage Tier |
|---|---|---|---|
| Session conversation logs | 30 days | Automatic expiry | On-device (encrypted CoreData) |
| Voice signatures / voiceprint | Until explicit deletion | User action or app uninstall | Keychain (Secure Enclave) |
| Health metrics (if enabled) | 90 days | Automatic expiry | On-device (encrypted CoreData) |
| Anonymized usage analytics | 90 days | Automatic expiry | Backend (aggregated only) |
| Crash reports | 180 days | Automatic expiry | Apple infrastructure (standard) |
| User preferences | Until app uninstall | App removal | On-device (UserDefaults) |
| Cached responses | 7 days or 100MB cap | LRU eviction or expiry | On-device (URLCache) |

### 3.2 Automatic Purge Implementation

```swift
class DataRetentionManager {
    /// Runs daily via BGAppRefreshTask
    func performScheduledPurge() async {
        let now = Date()

        // Purge session logs older than 30 days
        let sessionCutoff = now.addingTimeInterval(-30 * 24 * 3600)
        try await conversationStore.deleteEntries(olderThan: sessionCutoff)

        // Purge health metrics older than 90 days
        let healthCutoff = now.addingTimeInterval(-90 * 24 * 3600)
        try await healthMetricStore.deleteEntries(olderThan: healthCutoff)

        // Purge expired cache entries
        URLCache.shared.removeAllCachedResponses()

        // Log purge event (no PII in log)
        Logger.privacy.info("Scheduled data purge completed at \(now)")
    }
}
```

### 3.3 Data at Rest Encryption

All on-device data uses `NSFileProtectionComplete`, meaning files are encrypted with a key derived from the user's passcode and the device UID. Data is inaccessible when the device is locked.

For especially sensitive data (voice signatures, auth tokens), the Keychain is used with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, which additionally prevents migration to other devices via backup.

---

## 4. GDPR / CCPA Compliance Checklist

### 4.1 GDPR (General Data Protection Regulation)

| Requirement | Status | Implementation |
|---|---|---|
| Lawful basis for processing | Consent (Art. 6(1)(a)) | Explicit opt-in at first launch |
| Right to access (Art. 15) | Supported | Export all data via Settings > Privacy > Export My Data |
| Right to erasure (Art. 17) | Supported | Delete all data via Settings > Privacy > Delete All Data |
| Right to portability (Art. 20) | Supported | JSON export of conversation history and preferences |
| Data minimization (Art. 5(1)(c)) | Enforced | PII scrubbing, no unnecessary data collection |
| Purpose limitation (Art. 5(1)(b)) | Enforced | Data used solely for voice assistant functionality |
| Storage limitation (Art. 5(1)(e)) | Enforced | Automatic retention purge (see Section 3) |
| Data Protection Impact Assessment | Completed | On file, reviewed quarterly |
| Data Processing Agreement (DPA) | Signed | With Anthropic (Claude API provider) |
| Breach notification (Art. 33/34) | Process defined | 72-hour notification to supervisory authority |

### 4.2 CCPA (California Consumer Privacy Act)

| Requirement | Status | Implementation |
|---|---|---|
| Right to know | Supported | Privacy dashboard in app settings |
| Right to delete | Supported | One-tap data deletion |
| Right to opt-out of sale | N/A | No data is sold, ever |
| Non-discrimination | Enforced | Feature parity regardless of privacy choices |
| Financial incentive disclosure | N/A | No financial incentives tied to data sharing |

### 4.3 Additional Jurisdictional Compliance

- **PIPEDA (Canada):** Consent-based processing, data stored in-region when using PCC
- **LGPD (Brazil):** Explicit consent, lawful basis documented
- **POPIA (South Africa):** Purpose-specific processing, data minimization enforced
- **APPI (Japan):** Cross-border transfer protections via PCC routing

---

## 5. Encryption Requirements

### 5.1 At Rest

| Component | Algorithm | Key Length | Key Management |
|---|---|---|---|
| CoreData stores | AES-256 (via NSFileProtection) | 256-bit | iOS Data Protection (hardware UID + passcode) |
| Keychain items | AES-256-GCM (Secure Enclave) | 256-bit | Hardware-bound, non-exportable |
| Cache files | AES-256 (via NSFileProtection) | 256-bit | iOS Data Protection |
| UserDefaults | AES-256 (via NSFileProtection) | 256-bit | iOS Data Protection |

### 5.2 In Transit

| Channel | Protocol | Cipher Suite | Certificate Pinning |
|---|---|---|---|
| Claude API requests | TLS 1.3 | TLS_AES_256_GCM_SHA384 | Yes (SPKI pin + backup) |
| PCC requests | TLS 1.3 + Apple Attestation | Hardware-attested channel | Implicit (PCC infrastructure) |
| Analytics (if enabled) | TLS 1.3 | TLS_AES_256_GCM_SHA384 | Yes |
| OTA updates | HTTPS (App Store) | TLS 1.3 | Apple infrastructure |

### 5.3 Certificate Pinning Implementation

```swift
class APISessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedSPKIHashes: Set<String> = [
        "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",  // Primary
        "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",  // Backup
    ]

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustCopyCertificateChain(serverTrust)?.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let serverSPKIHash = certificate.spkiSHA256Hash
        if pinnedSPKIHashes.contains(serverSPKIHash) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            Logger.privacy.error("Certificate pinning validation failed")
        }
    }
}
```

---

## 6. User Consent Flow

### 6.1 First Launch Consent

On first launch, the user is presented with a stepped consent flow before any data processing begins:

1. **Welcome screen:** Overview of the assistant's capabilities
2. **Privacy summary:** Plain-language explanation of what data is collected and how it is used
3. **Microphone permission:** iOS system prompt for microphone access, preceded by a custom explanation screen
4. **Speech recognition permission:** iOS system prompt for on-device speech recognition
5. **Optional analytics consent:** Opt-in toggle for anonymized usage analytics (default: off)
6. **Confirmation:** Summary of selected privacy preferences with a "Get Started" button

No audio capture, speech recognition, or API communication occurs until all required consents are granted. If the user declines microphone or speech recognition permissions, the app displays a text-input-only fallback mode.

### 6.2 Ongoing Consent Management

Users can review and modify their consent choices at any time via **Settings > Privacy**:

- **Microphone access:** Revoke via iOS Settings (app prompts re-consent if re-enabled)
- **Speech recognition:** Revoke via iOS Settings
- **Analytics:** Toggle on/off within the app
- **Conversation history:** Toggle storage on/off (if off, no conversations are persisted)
- **Voice signature:** Enable/disable speaker recognition

### 6.3 Consent Versioning

Each consent event is stored locally with a version identifier. When the privacy policy is updated, users are re-prompted for consent on the changed terms only. The consent log is stored on-device and is included in data export requests.

```swift
struct ConsentRecord: Codable {
    let consentType: ConsentType
    let version: String          // e.g., "2.1.0"
    let granted: Bool
    let timestamp: Date
    let policyHash: String       // SHA-256 of the policy text at time of consent
}
```

---

## 7. Data Deletion Procedures

### 7.1 User-Initiated Deletion

Users can delete their data through three mechanisms:

1. **In-app deletion (Settings > Privacy > Delete All Data):**
   - Deletes all conversation history, cached responses, and preferences
   - Removes voice signature from Keychain
   - Resets consent records (re-prompts on next launch)
   - Sends a deletion confirmation request to the backend to purge any session identifiers
   - Completes within 5 seconds for typical data volumes

2. **App uninstall:**
   - iOS automatically removes all app sandbox data
   - Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` are also removed
   - Backend session identifiers expire per retention policy (30 days)

3. **GDPR/CCPA deletion request (via email or web form):**
   - Processed within 30 days (GDPR requirement)
   - Covers any backend-stored session metadata
   - Confirmation sent to the user upon completion

### 7.2 Backend Deletion

Upon receiving a deletion request (user-initiated or automated retention expiry):

1. All session records matching the opaque session UUID are marked for deletion
2. Records are purged from primary storage within 24 hours
3. Records are purged from backups within 30 days
4. A deletion receipt is generated and stored for audit purposes (receipt contains no user data)

### 7.3 Verification

After deletion, the app performs a self-audit:

```swift
func verifyDeletion() async -> DeletionVerificationResult {
    var issues: [String] = []

    // Check CoreData stores are empty
    let conversationCount = try await conversationStore.count()
    if conversationCount > 0 { issues.append("Conversations not fully purged") }

    // Check Keychain items are removed
    let keychainItems = try KeychainManager.allItems(service: bundleIdentifier)
    if !keychainItems.isEmpty { issues.append("Keychain items remain") }

    // Check cache directory is empty
    let cacheSize = try FileManager.default.sizeOfDirectory(at: cacheURL)
    if cacheSize > 0 { issues.append("Cache not fully cleared") }

    return DeletionVerificationResult(success: issues.isEmpty, issues: issues)
}
```

---

## 8. Third-Party Data Sharing Policies

### 8.1 Core Policy

**No user data is shared with, sold to, or made accessible to any third party.** The only external service that receives any data is the Claude API (Anthropic), and it receives only:

- Anonymized, PII-scrubbed transcript text
- An opaque session UUID (not linkable to the user's identity)
- Language/locale preference

### 8.2 Anthropic (Claude API) Data Handling

Per the data processing agreement with Anthropic:

- Request data is not used to train or improve Claude models
- Request data is not retained beyond the processing window (real-time streaming)
- Anthropic does not have access to the user's identity, device, or location
- API logs are retained by Anthropic for abuse prevention (max 30 days), containing only request metadata (timestamp, token count), not content

### 8.3 Apple

Standard Apple platform data flows apply:

- Crash reports (if user opted in via iOS Settings) are sent to Apple
- App Store analytics (if user opted in) are shared with Apple
- On-device speech recognition does NOT transmit audio to Apple (SFSpeechRecognizer with `requiresOnDeviceRecognition = true`)

### 8.4 No Advertising or Analytics SDKs

The application contains zero third-party analytics, advertising, or tracking SDKs. No data is shared with ad networks, data brokers, or analytics platforms.

---

## 9. Privacy Audit Schedule

### 9.1 Regular Audits

| Audit Type | Frequency | Performed By | Scope |
|---|---|---|---|
| Automated data flow scan | Every CI build | CI pipeline (static analysis) | Detect new network calls, new data stores |
| Manual privacy review | Quarterly | Engineering + Legal | Full data flow, consent flow, retention compliance |
| Penetration testing | Biannually | External security firm | Network interception, local data extraction, API abuse |
| DPIA review | Annually | Data Protection Officer | Full Data Protection Impact Assessment update |
| Third-party dependency audit | Monthly | Engineering (automated) | Check dependencies for data collection behavior |

### 9.2 Automated Privacy Checks (CI/CD)

The following checks run on every pull request:

1. **Network call inventory:** Static analysis to ensure no new endpoints are added without privacy review
2. **NSFileProtection audit:** Verify all new file writes use `NSFileProtectionComplete`
3. **Keychain access audit:** Flag any new Keychain reads/writes for manual review
4. **PII detector coverage:** Ensure PII scrubber unit tests cover all known PII patterns
5. **Dependency scan:** Check for known privacy-invasive transitive dependencies

### 9.3 Incident Response

If a privacy incident is detected:

1. **T+0:** Incident identified and classified (severity 1-4)
2. **T+1h:** Incident response team assembled, initial assessment complete
3. **T+4h:** Root cause identified, mitigation deployed or in progress
4. **T+24h:** Affected users notified (if severity 1 or 2)
5. **T+72h:** Supervisory authority notified (if GDPR-reportable)
6. **T+30d:** Post-incident review completed, preventive measures implemented

---

## 10. Privacy by Design Principles

The following principles guide all design and implementation decisions:

1. **Minimize:** Collect only what is strictly necessary for functionality
2. **Localize:** Process data on-device whenever technically feasible
3. **Anonymize:** Strip all PII before any data leaves the device
4. **Encrypt:** Protect all data at rest and in transit with strong encryption
5. **Expire:** Automatically delete data after its retention period
6. **Empower:** Give users full visibility and control over their data
7. **Verify:** Continuously audit compliance through automated and manual processes
8. **Document:** Maintain clear, versioned records of all data handling practices
