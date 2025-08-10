# Event Validation Patterns

This document summarizes client-to-server event patterns in NexusGuard and the corresponding validation performed on the server. Each handler verifies the authenticity of the client's security token and checks relevant state to prevent tampering.

## SECURITY_REQUEST_TOKEN
- Ensures the client hash is a valid string before generating and returning a security token.

## DETECTION_REPORT
- Validates the security token.
- Retrieves the player's session before passing data to the detections module.

## SYSTEM_RESOURCE_CHECK
- Validates the security token.
- Requires the resource list to be a table and compares it against whitelist/blacklist configuration.

## SYSTEM_ERROR
- Validates the security token.
- Records the error in the player's session metrics.

## ADMIN_SCREENSHOT_TAKEN
- Validates the security token.
- Requires a non-empty screenshot URL string before logging and forwarding the event.

## ADMIN_SCREENSHOT_FAILED
- Validates the security token.
- Requires a textual error reason and records the failure for review.

## NEXUSGUARD_POSITION_UPDATE
- Validates the security token.
- Confirms position data is a `vector3` and updates session metrics before delegating to position validation logic.

## NEXUSGUARD_HEALTH_UPDATE
- Validates the security token.
- Uses the session data to verify health and armor values via the detections module.

## NEXUSGUARD_WEAPON_CHECK
- Validates the security token.
- Compares reported clip counts against configured weapon limits and raises detections on mismatch.

All handlers rely on `NexusGuardServer.Security.ValidateToken` for token authentication and make use of session data retrieved via `NexusGuardServer.GetSession` when necessary.
