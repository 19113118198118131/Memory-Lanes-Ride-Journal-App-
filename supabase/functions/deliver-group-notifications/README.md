# Group notification delivery

This Edge Function drains `notification_outbox` and sends APNs alert pushes.
It is intentionally dormant until the Apple Developer push key is available.

Required Supabase Edge Function secrets:

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_PRIVATE_KEY` (the complete `.p8` content)
- `APNS_TOPIC` (`app.memorylanes.native`)
- `PUSH_WORKER_SECRET`

Invoke it from a one-minute scheduler with the same value in the
`x-worker-secret` header. Before activation, enable the Push Notifications
capability for the production App ID and install a distribution build on a
physical iPhone.
