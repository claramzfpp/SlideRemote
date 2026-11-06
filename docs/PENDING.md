# SlideRemote: review findings

---

## 1. Project state

**What it is:** the iPad shows a PDF; the iPhone controls the slides via MultipeerConnectivity; the
Apple Watch tells the iPhone about a wrist twist (each gesture = next slide).

**Already done (all on `main`, 119 tests passing, iOS and watchOS targets compiling):**

| Phase | Delivery |
|---|---|
| Architecture | Transport and PDF-loading protocols, ViewModels on both sides, `RemoteCommand`/`RemoteService` in `Model/` |
| 1 | The iPad approves each invitation in an alert; one iPhone at a time; the iPhone picks the iPad from a list (no automatic invitation) |
| 2 | 6-digit code on the iPad screen, validated inside the encrypted session; 3 wrong codes lock; 60 s deadline to authenticate; "Disconnect iPhone" button |
| 3 | Limit of 10 commands/s per session; the receiver only forwards messages from the approved peer |
| 4 | Resume without typing the code: in-memory credential only, HMAC-SHA256 proof with a single-use challenge, rotation on every authentication |
| 5 | `os.Logger` instead of `print` (`.private` names), `.gitignore`, 200 MB PDF limit, permission texts |

**Decisions already made (do not reopen without a reason):**
- Nothing goes to the Keychain; the reconnect credential lives in memory only.
- The iPad approval alert still appears on resume; only the **code** is no longer asked for.
- The bundle ID stays `project.SlideRemote` (changing it only makes sense before publishing or using TestFlight).
- Silent reconnection (no alert) was rejected: it would require the iPad to accept invitations without approval.
- The `slide-remote-with-mac-future-feature` branch exists and was never touched.

**What was NEVER tested:** the flow with real Multipeer between an iPhone and an iPad. Multipeer
is not reliable in the simulator. See the script in section 7.

---

## 1. Code map

```
SlideRemote/
  Model/        PairingCode, PairingSession, InvitationPolicy, RemoteMessage, RemoteCommand,
                HexToken, ResumeProof, CommandThrottle, Presentation, RemoteService, AppLog
  iPad/
    Domain/       CommandReceiving, PDFLoading
    Data/         MultipeerCommandReceiver, SecurityScopedPDFLoader
    Presentation/ PresentationViewModel, PresentationView, PDFKitView
  iPhone/
    RemoteCommandSending.swift   (RemoteCommandSending and MovementSource protocols, DiscoveredPeer)
    Data/         MultipeerRemoteSender
    Presentation/ RemoteViewModel, RemoteView
SlideRemoteWatch/  WatchArmDetector, WatchConnectivityManager (also compiled on iOS), ContentView
SlideRemoteTests/  Model/, iPad/, iPhone/   (Swift Testing)
```

Current constants: invitation alert 25 s · iPhone invitation expires in 30 s · authentication
deadline 60 s · 3 code attempts · 10 commands/s · PDF up to 200 MB · Watch gesture cooldown 1 s.

---

## 2. Batch 1: robustness and lock-ups (start here)

- [ ] **1.1 `MCPeerID` can crash the app on launch** (high, confirmed by Apple's documentation)
  - `MCPeerID(displayName:)` throws if the name is longer than 63 bytes in UTF-8 or empty.
  - Where: `MultipeerCommandReceiver.swift` (`peerID` creation) and `MultipeerRemoteSender.swift` (same).
  - Fix: truncate by UTF-8 bytes on a `Character` boundary; if empty, use "iPad"/"iPhone".
    Needs a pure test (long name, with accents/emoji, empty).

- [ ] **1.2 Three wrong codes create a new session instead of locking** (medium, confirmed)
  - `PresentationViewModel.handlePairing`, `.locked` case: does `disconnectPeer()` and then
    `startNewSession()`. `.pair` messages already queued land in the new session (new code, 3
    new attempts), bypassing the "locked forever" behavior of `PairingSession`.
  - The `startNewSession()` there is unnecessary: a new peer needs a new invitation, which already creates the session.
  - Fix: on `.locked`, just disconnect and end the session (the equivalent of `disconnectPhone()`).
  - **Warning:** the tests `threeWrongCodesLockDisconnectAndRenewCode` and `oldCodeDoesNotWorkAfterLock`
    enshrine the current behavior and must be rewritten first (TDD).

- [ ] **1.3 iPhone stuck with no way out** (medium, confirmed)
  - `.connecting`: `select` changes the phase before `connect(to:)`, which silently returns if the iPad
    vanished from the list. No event arrives and only the Cancel button gets the user out.
    `DiscoveredPeer.id` is a fresh `UUID()` on every discovery, so an old row may point to a dead id.
  - `.verifying` ("Verifying code..." / "Resuming connection..."): there is no timeout and no Cancel button.
    If the iPad ignores the message (throttle, dropped session), the screen stays there until the iPad's 60 s deadline drops the connection.
  - **Ghost invitation:** cancelling on the iPhone calls `session.disconnect()`, which does not cancel an in-flight invitation.
    The alert stays on the iPad for up to 25 s; if the presenter taps "Allow", a session, a code and a 60 s deadline
    are born for a peer that does not exist (and real invitations are declined during that period).
  - Fixes: `connect(to:)` returns `Bool` (or emits `isConnected = false`) and the VM goes back to `.searching` with a notice;
    own timeout and a "Cancel" button in `.verifying`; use `session.cancelConnectPeer(_:)` in `disconnect()` when
    not yet connected; on the iPad, when a new invitation from the same `MCPeerID` arrives with one pending, replace the old handler.

- [ ] **1.5 Out-of-order event wipes the deadline of the newly approved peer** (low/medium, hypothesis)
  - A late `.notConnected` (from an old peer) arrives while the new approved peer is still connecting
    (`connectedPeers` empty) → `onConnectionChange(false)` → `endSession()` clears the session, the code and **cancels the deadline**.
    The peer connects later with no session and no deadline, holding the slot until the presenter disconnects manually.
  - Variant: `startNewSession()` after `.locked` runs with no new deadline and no peer.
  - Fixes: only call `endSession` if there is no approved/active peer; or do not cancel the deadline of an approved peer;
    or restart the deadline whenever a new session starts.
  - Related (hypothesis): a late `.notConnected` from the iPhone's own `disconnect()` may bring down a new attempt
    to the same peer (`update` in `MultipeerRemoteSender`).

---

## 3. Batch 2: lifecycle and DoS

- [ ] **2.1 Multipeer is never restarted** (medium, code confirmed; background behavior is a hypothesis)
  - `receiver.start()` runs in the VM's `init` and `stop()` is never called; the iPhone's browser never stops.
    Nothing observes `scenePhase`; `didNotStartAdvertisingPeer` only logs and `didNotStartBrowsingForPeers` does not even exist.
  - Effect: after being in the background, the iPhone stays on "Searching for iPad..." forever. If the **local network** permission
    is denied, the error is silent.
  - Fix: restart advertising/browsing on `.active`; expose the advertising/browsing error to the VM and show a hint
    (same network, Bluetooth, Local Network permission).

- [ ] **2.3 Invitation spam** (medium, path confirmed)
  - Whoever invites in a loop makes the alert appear over the slides (25 s at a time); with an invitation pending, the legitimate
    iPhone's is silently declined. Declining/expiring imposes no cooldown.
  - Fixes: cooldown/backoff per `MCPeerID` after a decline or timeout; cap on alerts per minute; a **pairing window**
    opened by the presenter ("Pair iPhone" button, time-limited); stop advertising after authenticating.

- [ ] **2.4 Peer identity is only the `displayName`** (medium; real severity depends on testing on a device)
  - It is spoofable and the alert only shows the name. On iOS 16+, `UIDevice.current.name` tends to return a generic name
    ("iPhone"/"iPad") without the user-assigned-device-name entitlement; there is no `.entitlements` in the repo.
    In that case devices collide and `credentials[name]` on the iPhone may associate iPad X's credential with iPad Y
    (Y answers `resumeRejected` and `forgetCredential()` erases X's).
  - **First:** confirm on a device what `UIDevice.current.name` returns.
  - Possible fixes: an installation UUID advertised in `discoveryInfo` and used as the key; clearer alert text
    ("only accept if you just tapped connect on your iPhone"); show something besides the name in the iPhone's list.
    Remember that the invitation `context` is **not encrypted**.

- [ ] **2.5 Small hardening items** (low)
  - Limit messages to ~128 bytes **before** parsing (`RemoteMessage.init?(data:)`) and check the peer before decoding.
  - At most 1 to 2 resumes per approved invitation; after that, force the code flow.
  - Expire the credential (1 to 2 h) and clear it when the iPad goes to the background.
  - `.locked` may not reach the iPhone (`send` followed by an immediate `disconnect()`): the iPhone must forget the credential
    on **any** drop during `.verifying`. Today, if `.notConnected` arrives before `.credential`, the credential is ignored
    and the future resume fails. Option: delay `disconnectPeer()` on the iPad after `.locked`.
  - `SecurityScopedPDFLoader`: if `fileSize` comes back `nil` (`try?`, e.g. an iCloud file not downloaded), the limit is skipped.
    Treat as an error or read with a cap; consider lowering the limit to 50 MB.
  - `rejected:N` accepts `+3`/`-0` (harmless); a fake iPad can keep the iPhone on the code screen (the user cancels).

---

## 4. Batch 3: architecture and tests (global CLAUDE.md rules)

- [ ] **3.1 Fragile timing tests:** `PresentationViewModelTests` uses `Task.sleep` of 300 to 500 ms against deadlines of
  30 to 150 ms. Inject a `Clock` (manual test clock) and remove the sleeps. The "does not fire afterwards" tests pass
  by accident if the timer breaks in some other way.

- [ ] **3.2 Real receiver and sender untested.** `FakeCommandReceiver` reimplements the policy instead of testing it and is
  **more permissive than the real one** (it does not mark "approved and still connecting" as an active peer; it would accept a second invitation).
  `FakeSender` does not filter by `targetPeer` and `connect()` never fails, which is why item 1.3 does not show up in the tests.
  Proposal: extract the routing (pending invitation, approved, active, message filter) into a pure type (`PeerGate`)
  that is testable, leaving the Multipeer shell thin.

- [ ] **3.3 Watch untested.** Extract the twist decision (`rate.x < -4`, dominance >= 0.9) into a pure `WristTwistClassifier`
  and test it with measured values; test the cooldown with an injected clock. Document that the division by `rotation`
  only runs after `rate.x < -4` (never zero).

- [ ] **3.4 Frameworks leaking into the domain:**
  `import PDFKit` in `PDFLoading` (the VM holds a `PDFDocument`; it only needs `pageCount`);
  `CryptoKit` in `ResumeProof` (use a signing protocol with the CryptoKit implementation outside Model);
  `Combine`/`AnyPublisher` in `RemoteCommandSending` (the iPad's `CommandReceiving` already uses closures; make the two symmetric);
  `OSLog`/`Bundle` in `AppLog` inside `Model/`, and the iPad VM calling `AppLog` directly.
  `PDFLoadError` mixes a domain error with UI text.

- [ ] **3.5 Structure:** `Model/` holds entities, value objects, a wire DTO, policy and the logger. Proposal:
  `Domain/` (`Presentation`, `PairingCode`, `PairingSession`, `HexToken`, `CommandThrottle`, `InvitationPolicy`, `RemoteCommand`),
  `Data/Wire/` (`RemoteMessage`, `RemoteService`), `Infrastructure/` (`AppLog`). Mirror it in the tests
  (today `PresentationViewModelTests` is in `iPad/` and the code is in `iPad/Presentation/`). The iPhone has no `Domain/`.

- [ ] **3.6 `RemoteMessage` mixes directions.** Each VM does a full `switch` and ignores the "other side" cases
  (`case ... break`). Splitting into `PhoneToPadMessage` and `PadToPhoneMessage` makes the compiler guarantee the direction.

- [ ] **3.7 `PresentationViewModel` (~230 lines)** accumulates the pairing state machine, invitation lifecycle and timers, rate limit and PDF.
  Extract a pairing controller that is testable without `Task.sleep`; the VM only publishes state.
  On the iPhone side, `PairingPhase` and the rules (resume vs. ask for the code) are also domain.

- [ ] **3.8 Watch shared between targets.** `WatchConnectivityManager` compiles in both targets (via
  `membershipExceptions`) with opposite roles, and `extension WatchConnectivityManager: MovementSource {}` sits on the iPhone.
  Split into a sender (Watch) and a receiver (iPhone), with the `"movement"`/`"wristTwist"` keys in a small shared type.
  `RemoteView` uses `WatchConnectivityManager.shared` directly; inject it. `MainActor.assumeIsolated` in
  `startListeningToWatch` is only safe because the manager does `DispatchQueue.main.async`; type the closure as `@MainActor`.
  Conformance to a `@MainActor` protocol becomes an error in Swift 6.

- [ ] **3.9 Asymmetry between receiver and sender** (one `@MainActor` with `nonisolated` + `Task`, the other with `DispatchQueue.main.async`);
  `MCPeerID`/`MCSession` are created in duplicate. Extract a common factory. The three empty `MCSessionDelegate` handlers
  repeat on both sides.

---

## 5. Known limitations that remain

- **Relay MITM (medium/high, not fixed):** the Multipeer session is encrypted but does **not authenticate** the peer (`securityIdentity: nil`).
  A fake iPad with the same name can relay the code and the resume to the real iPad: the HMAC proves possession of the credential, but does not bind the
  proof to the channel, and the iPhone accepts `.pairingResult(.accepted)` from any peer. Truly closing this requires mutual authentication
  (a PAKE such as SPAKE2/CPace, or a self-signed certificate with a fingerprint pinned after the first pairing). It is a big piece of work;
  for use in nearby presentations, the plan is to document the limit and deal with it later.
- An authenticated malicious peer can still push up to 10 slides/s (insider risk).
- There is no silent reconnection: the presenter still taps "Allow" and the iPhone still picks the iPad from the list.
- The credential is per iPad **name** on the iPhone (see 2.4); the HMAC prevents this from leaking the credential.

---

## 6. How to run and conventions

**User rules (`~/.claude/CLAUDE.md`):** strict Clean Architecture, TDD (red test first, `test:` → `feat:` →
`refactor:` commits), self-validating value objects, framework-free domain, comments only for the why, `docs:` in a separate commit,
never read/log `.env`/Keychain, do not install dependencies or touch the Xcode project structure without permission.
Limited test runs: only the relevant suite, in the background, killed after 30 s.

**Tests** (the `SlideRemoteTests` target uses Swift Testing and is already in the `SlideRemote` scheme). Replace the id with that of an available
iPhone simulator (`xcrun simctl list devices available`) and boot it first (`xcrun simctl boot <id>; xcrun simctl bootstatus <id> -b`):

```bash
xcodebuild build-for-testing -scheme SlideRemote -destination 'platform=iOS Simulator,id=<ID>' -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -scheme SlideRemote -destination 'platform=iOS Simulator,id=<ID>' -derivedDataPath /tmp/dd -only-testing:SlideRemoteTests/<Suite>
xcodebuild build -scheme "SlideRemoteWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Pitfalls already found:
- A constant `RandomNumberGenerator` inside `Int.random(in:using:)` loops forever (rejection sampling). Do not use that in fakes.
- `#expect` does not accept calling a `mutating` method directly: store the result in a variable first.
- The app folder uses *synchronized groups*: new files are picked up automatically, with no `.pbxproj` edit.

