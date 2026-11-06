# SlideRemote: review findings

Document for resuming the work in another session. It collects what three independent reviews
(security, concurrency/correctness, and architecture/tests/UX) found in the code after
security Phases 1 to 5.

> **Read before acting.** The reviewers only **read** the code; nobody ran the app on devices.
> Each item carries its confidence: **confirmed** (the code proves it) or **hypothesis** (depends on
> real Multipeer/SwiftUI behavior). Line numbers were valid at commit
> `72186b3` and may have moved.

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

## 2. Code map

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

## 3. Batch 1: robustness and lock-ups (start here)

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

- [ ] **1.4 Pairing code visible to the audience** (medium/high, confirmed)
  - `PresentationView`: the code appears at 72 pt **over the slide** while the iPhone is not authenticated, and again
    if the iPhone drops and reconnects. With the iPad projected, anyone can see it.
  - Fixes: show it only on the pre-presentation screen, or on demand ("Show code"), or hide it after ~10 s/on touch;
    show a countdown of the deadline; optionally hide it if `UIScreen.main.isCaptured`.

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

## 4. Batch 2: lifecycle and DoS

- [ ] **2.1 Multipeer is never restarted** (medium, code confirmed; background behavior is a hypothesis)
  - `receiver.start()` runs in the VM's `init` and `stop()` is never called; the iPhone's browser never stops.
    Nothing observes `scenePhase`; `didNotStartAdvertisingPeer` only logs and `didNotStartBrowsingForPeers` does not even exist.
  - Effect: after being in the background, the iPhone stays on "Searching for iPad..." forever. If the **local network** permission
    is denied, the error is silent.
  - Fix: restart advertising/browsing on `.active`; expose the advertising/browsing error to the VM and show a hint
    (same network, Bluetooth, Local Network permission).

- [ ] **2.2 iPhone screen locks during the presentation** (medium, product hypothesis)
  - With the Watch in control, the user does not touch the iPhone; the screen locks, the app suspends, Multipeer drops.
  - Fix: `UIApplication.shared.isIdleTimerDisabled = true` while `phase == .paired`.

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

## 5. Batch 3: architecture and tests (global CLAUDE.md rules)

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

## 6. Batch 4: UX, constants and documentation

- [ ] **4.1 UX**
  - No haptic on the iPhone when sending next/previous or when pairing; the Watch vibrates on detection, **before** knowing whether the gesture was delivered
    (`guard isReachable` silently drops it). Vibrate `.success` only when sent and `.failure` if there is no connection.
  - Auto-submit when 6 digits are typed; "Confirm" disabled until then.
  - The iPhone is not told when the iPad closes the presentation (it stays `.paired` and commands become no-ops) nor when the iPad
    has no PDF.
  - `fileImporter` ignores `.failure`; `loadError` only shows on the empty screen.
  - Empty states without a hint (same network, Bluetooth, Local Network permission); red `notice` without a "Try again" action.
  - The alert title is empty during the close animation (`pendingInvitation ?? ""`). If an invitation arrives while the file picker is
    open, the alert may only appear later and expire (25 s) without the presenter seeing it.
  - Watch: minimal UI, no "iPhone connected/out of range" state and no indication that the gesture only advances.
  - Possible visual bug (**to be confirmed**): in dark mode the white `ArrowButton` icon may sit on a light circle.
  - Accessibility: fixed fonts (`.system(size: 72/32/20)`) do not scale with Dynamic Type; there is no VoiceOver announcement when
    pairing changes; the label "Previous Slide" should be "Previous slide".
  - Previews (`#Preview { PresentationView() }` and `RemoteView()`) spin up the real Multipeer. Build the composition in a root
    (`SlideRemoteApp`) with injection.

- [ ] **4.2 Named constants:** gather 25 s, 60 s, 30 s, 10/s and 3 attempts into a `PairingPolicy`. The iPhone invitation (30 s) should
  derive from the iPad deadline (25 s) plus a margin (today 5 s, which is short). Also `0.02` (50 Hz) on the Watch and the fixed UI measurements.

- [ ] **4.3 Comments and documentation**
  - Delete the didactic block about Multipeer at the top of `MultipeerCommandReceiver.swift` and the inline comments that only translate the API.
  - Fix the outdated comment "Before authenticating, or without a PDF..." in `PresentationViewModel` (the `guard` only looks at authentication).
  - Remove comments that repeat the name (`currentPage`, `codeError`, `CommandReceiving`, "preview: no action").
  - **A `docs:` pass in its own commit** (CLAUDE.md rule) for the invariants the name does not say:
    `PairingCode` (why ASCII only and 6 digits), `HexToken.generate` (CSPRNG), `ResumeProof.compute` (the key is the hex string in UTF-8,
    not the decoded bytes; both ends must repeat it), `CommandThrottle` (injected monotonic instant, `max(…, 1)`),
    `PairingSession.submit` (idempotent after authentication), and the reason for constant time.

- [ ] **4.4 Cleanup and names:**
  `RemoteService.type = "number-sync"` and `NSBonjourServices` (`_number-sync._tcp`) come from the old prototype (change all three places together);
  Watch headers still say "RotateWristWatch"; `RemoteCommand.data`/`init?(data:)` may be used only by tests (confirm with grep);
  `HexToken.swift` has free functions and a `private extension` just to work around a name collision; `PairingCode.matches` reimplements the XOR
  instead of using `constantTimeEquals`; `CommandThrottle` could have a `reset()` instead of the VM keeping `throttleTemplate`;
  `Presentation(pageCount: 0)` is possible (`init?` for `pageCount < 1`); `NSMotionUsageDescription` on the iPhone target is probably unnecessary
  (only the Watch uses CoreMotion); three old commits without a Conventional Commits prefix (before CLAUDE.md).

---

## 7. Real-device test script (not done yet)

Needs **one iPhone, one iPad and, preferably, a second iPhone** as an intruder.

1. Normal pairing: alert on the iPad, code visible, type it on the iPhone, arrows work, the Watch advances the slide.
2. Second iPhone trying to join during the presentation: declined **without** an alert.
3. Wrong code 3 times: the iPhone is disconnected and the iPad generates a new code (today it creates a new session; see 1.2).
4. Decline the invitation: the iPhone returns to the list with "The iPad declined or did not respond".
5. Approve and **do not** type the code: after 60 s the iPad disconnects and accepts another invitation.
6. "Disconnect iPhone" in the middle of the presentation: the iPad goes back to accepting invitations.
7. Wi-Fi drops, then pick the same iPad and tap "Allow": it must resume **without** asking for the code.
8. "Disconnect iPhone" and reconnect: it must ask for the code again. Closing and reopening the iPad app: same.
9. Check what `UIDevice.current.name` returns on each device (item 2.4) and whether a long name crashes the app (item 1.1).
10. Check that the per-peer filter does not drop everything: the iPad compares `MCPeerID` with `==` in `didReceive`. If pairing never
    completes even with the right code, the first suspect is that `guard` in `MultipeerCommandReceiver`.
11. Leave the app in the background and come back (item 2.1); lock the iPhone screen during the presentation (item 2.2);
    cancel an invitation from the iPhone and see whether the alert gets stuck on the iPad (item 1.3).

---

## 8. Known limitations that remain

- **Relay MITM (medium/high, not fixed):** the Multipeer session is encrypted but does **not authenticate** the peer (`securityIdentity: nil`).
  A fake iPad with the same name can relay the code and the resume to the real iPad: the HMAC proves possession of the credential, but does not bind the
  proof to the channel, and the iPhone accepts `.pairingResult(.accepted)` from any peer. Truly closing this requires mutual authentication
  (a PAKE such as SPAKE2/CPace, or a self-signed certificate with a fingerprint pinned after the first pairing). It is a big piece of work;
  for use in nearby presentations, the plan is to document the limit and deal with it later.
- An authenticated malicious peer can still push up to 10 slides/s (insider risk).
- There is no silent reconnection: the presenter still taps "Allow" and the iPhone still picks the iPad from the list.
- The credential is per iPad **name** on the iPhone (see 2.4); the HMAC prevents this from leaking the credential.

---

## 9. How to run and conventions

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

---

## 10. Suggested order for the next session

1. **Batch 1** in TDD (1.1 to 1.5), starting with 1.1 (crash) and 1.2 (rewrite the two tests first).
2. **Test with real devices** (section 7): several items in batches 2 and 3 depend on real Multipeer behavior.
3. **Batch 2** (2.1 to 2.5), with the decision on the pairing window and peer identity (2.4).
4. **Batch 3** (injected clock, `PeerGate`, `WristTwistClassifier`, decoupling from frameworks).
5. **Batch 4** (UX, constants, `docs:` pass).
6. Decide whether the relay MITM (section 8) will be addressed.
