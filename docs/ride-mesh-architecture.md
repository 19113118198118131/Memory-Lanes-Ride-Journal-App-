# Ride Mesh Architecture

## Product Scope

Ride Mesh is a nearby messaging channel attached to one Memory Lanes group
ride. It is designed for ride-day coordination when mobile data is weak or
unavailable:

- members explicitly open Ride Mesh before discovery starts;
- only the current group ride is discoverable;
- text and four glanceable quick signals are supported;
- messages queue in the active session until a nearby rider appears;
- accepted packets relay across nearby group members with a bounded hop count;
- foreign, stale, duplicated and tampered packets are silently discarded.

It is not an emergency service, a general public chat room or a replacement
for the server-backed event invitation and announcement workflow.

## Lobby And Web Handoff

The Supabase-backed group lobby is the cross-platform coordination layer.
Organisers and members can RSVP, check in, read host announcements and open the
shared route from either the web or native app.

Ride Mesh itself is an iPhone transport and cannot run in a desktop browser.
For eligible scheduled rides, the web lobby therefore exposes an explicit
iPhone handoff:

- on iPhone, `Open Ride Mesh` opens
  `memorylanes://group/{share-token}?open=mesh`;
- on desktop, `Copy iPhone Link` copies the universal web invite with
  `open=mesh`, ready to send to a rider's iPhone;
- the native app validates the group membership and RSVP state before opening
  the mesh screen;
- both nearby riders must open Ride Mesh for the same group before peer
  discovery begins. Discovery remains available while iOS backgrounds the
  visible mesh screen, subject to the normal CoreBluetooth execution budget.

The browser remains useful when Ride Mesh is unavailable: host announcements
and ride-day check-in are server-backed and work across platforms.

## Transport

Ride Mesh now runs two nearby transports concurrently behind
`RideMeshTransporting`:

1. `BluetoothRideMeshTransport` makes every iPhone a CoreBluetooth central and
   peripheral. It scans and advertises the same service, exchanges a
   ride-channel handshake, fragments encrypted packets to the negotiated BLE
   MTU, reassembles them with strict memory/time bounds and supports iOS
   central/peripheral background modes. This is the reception-independent path
   used when Airplane Mode is enabled but Bluetooth is turned back on.
2. `NearbyRideMeshTransport` uses MultipeerConnectivity over local Wi-Fi/AWDL
   as a faster opportunistic path when it is available.

`HybridRideMeshTransport` fans packets across both paths. The protocol-level
duplicate cache makes receiving the same packet over BLE and Wi-Fi harmless,
and transport-tagged ingress identities preserve split-horizon relay exclusion.
The UI reports the largest connected-path count rather than summing both paths,
so one rider visible on both radios is not shown twice.

Leaving the Ride Mesh screen stops both transports. Locking the screen or
temporarily backgrounding the app no longer stops the session explicitly;
CoreBluetooth may continue under iOS background rules. Force-quitting the app
still ends the active session.

Multipeer links use Apple's required transport encryption. Ride Mesh also
encrypts every application packet because Bluetooth and relay peers must be
treated as untrusted transports.

## Channel And Encryption

The group ride's random share token acts as the invitation capability:

1. SHA-256 derives a short, non-reversible advertised channel ID.
2. HKDF-SHA256 derives a 256-bit ride key using a versioned domain and salt.
3. ChaCha20-Poly1305 seals the sender, display name, body and quick-signal type.
4. Packet identity, channel, creation time and original TTL are authenticated
   as associated data.

All members holding the invite token share the group key. This protects the
conversation from unrelated nearby listeners but does not provide
member-specific identity verification. The UI therefore says "private to this
group ride", not "verified end-to-end identity".

## Abuse And Failure Bounds

- 280-character message limit
- 8 KiB encoded packet limit
- original TTL capped at 8; current default is 4
- six-hour acceptance window and five-minute future-clock tolerance
- 512-entry, six-hour duplicate cache
- 200-message in-memory timeline
- wrong-channel and unauthenticated packets never reach the UI
- queued messages remain in memory only for the active lobby session

No location, route geometry, account ID or Supabase access token is included in
the radio packet.

## Reference

The transport and protocol design was informed by the public-domain
`permissionlesstech/bitchat` project, inspected at commit
`0152196ac2648ef3f6a1bbab4f24f1a88e11b3b2`. Memory Lanes does not mirror or
embed the complete bitchat application or claim wire compatibility. It mirrors
the architecture where it fits a private group ride: a BLE store-and-forward
mesh, an additional higher-throughput path, encrypted application packets and
a transport-independent session.

Relevant design ideas retained:

- simultaneous BLE central/peripheral discovery and relay;
- fragmentation and bounded out-of-order reassembly;
- concurrent transport fan-out with protocol-level deduplication;
- authenticated encryption above the radio transport;
- TTL-bounded forwarding;
- bounded duplicate suppression;
- honest delivery and privacy states.

Unlike bitchat's BLE + Nostr design, Memory Lanes currently uses BLE + local
Wi-Fi/AWDL for live mesh traffic. Supabase remains the internet-backed group
lobby, RSVP, announcement and live-location layer; mesh chat is intentionally
ephemeral and nearby-only. Full bitchat parity would additionally require a
persistent sealed outbox, courier carry-and-forward, state restoration after
process termination, relay jitter/fan-out control, per-member Noise identity,
an internet relay transport and cross-platform protocol compatibility.

## Release Gate

Simulator tests cover encryption, expiry, queue flush, duplicate suppression,
relay exclusion, BLE fragmentation, out-of-order reassembly, peer isolation and
malformed/oversized frame rejection. Before enabling Ride Mesh in a production
release, test with at least two physical iPhones in Airplane Mode with Bluetooth
re-enabled, then repeat with screen lock and Local Network denied. Validate
reconnection, practical range, battery impact and permission recovery. Use a
third iPhone to validate a real two-hop BLE relay before describing the feature
as production mesh in release copy.
