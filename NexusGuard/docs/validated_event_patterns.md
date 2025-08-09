# Validated Event Patterns

This document records client-to-server events that include built-in validation.

## `SYSTEM_RESOURCE_CHECK`
- **Client**: `client/detectors/resourcemonitor_detector.lua` triggers the event with a list of running resources and the client's security token.
- **Server**: `server/server_main.lua` validates the security token, confirms the player's session, updates activity, and checks the provided resources against configured allow/deny lists.

## `NEXUSGUARD_WEAPON_CHECK`
- **Client**: `client/detectors/weaponmod_detector.lua` contains a commented example showing how the detector should send the weapon hash, clip count, and security token.
- **Server**: `server/server_main.lua` verifies the security token, ensures a valid player session, and compares the reported clip size to the configured threshold for that weapon.

These patterns ensure that sensitive client reports are authenticated and cross‑checked server-side before any action is taken.
