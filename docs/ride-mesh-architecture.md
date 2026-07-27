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

## Transport

Phase 1 uses Apple's `MultipeerConnectivity` framework. Each device advertises
and browses the `_ml-ridemesh._tcp` Bonjour service and connects only when the
advertised channel ID matches the active ride.

Discovery runs only while the Ride Mesh screen is visible and the app is
active. Leaving the screen or backgrounding the app stops advertising and
browsing; returning to the visible screen resumes the same in-memory session.

`RideMeshTransporting` isolates the framework from the session and UI. A later
CoreBluetooth transport can replace it without changing message models or
screens if physical ride testing shows that background discovery or denser
mesh topologies justify the additional radio complexity.

Multipeer links use Apple's required transport encryption. Ride Mesh also
encrypts every application packet because transport peers may relay packets.

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
embed the complete bitchat application; it implements a smaller,
group-ride-specific protocol behind its own transport seam.

Relevant design ideas retained:

- simultaneous nearby discovery and relay;
- authenticated encryption above the radio transport;
- TTL-bounded forwarding;
- bounded duplicate suppression;
- honest delivery and privacy states.

Deferred ideas include persistent sealed outboxes, courier carry-and-forward,
background CoreBluetooth restoration, per-member key verification, media,
internet relay fallback and cross-platform protocol compatibility.

## Release Gate

Simulator tests cover encryption, expiry, queue flush, duplicate suppression
and relay exclusion. Before enabling Ride Mesh in a production release, test
with at least two physical iPhones for Local Network permission handling,
discovery recovery, practical range, screen-lock behavior and battery impact.
Use a third iPhone to validate a real two-hop relay before describing the
feature as mesh-capable in release copy.
