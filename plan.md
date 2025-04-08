# NexusGuard Development Plan

## Phase 1: Core Detection Refinement & Server Authority

### Server-Side Speed/Teleport Checks (Guidelines 26, 27, 28)
*   Modify the `NEXUSGUARD_POSITION_UPDATE` handler in `server_main.lua` to better account for vertical velocity (falling, parachuting) to reduce false positives.
*   Add logic to temporarily suspend speed checks immediately after player spawn/respawn.
*   Ensure the `serverSideSpeedThreshold` from `config.lua` is used and potentially add other related config options (like `minTimeDiff` between checks).

### Server-Side Health/Armor Checks (Guidelines 29, 25)
*   Modify the `NEXUSGUARD_HEALTH_UPDATE` handler in `server_main.lua` to make the passive regeneration check less sensitive (e.g., require a larger increase or sustained increase).
*   Ensure `serverSideRegenThreshold` and `serverSideArmorThreshold` from `config.lua` are used.
*   **(Potentially Complex/Deferrable)** Enhance the health check to correlate health values with recent server-side damage events (requires hooking/tracking damage events). This significantly improves god mode detection accuracy.

### Other Server-Side Validations
*   Implement `NexusGuardServer.Detections.ValidateWeaponDamage` in `globals.lua` using `Config.WeaponBaseDamage`. (Addresses TODO from previous steps).
*   **(Optional)** Implement `NexusGuardServer.Detections.ValidateVehicleHealth` if reliable base values or methods exist.

### Review/Enhance Other Detectors (Guidelines 31, 33, 34)
*   Review `noclip_detector.lua` logic. Consider adding server-side position validation overlap checks within the `NEXUSGUARD_POSITION_UPDATE` handler.
*   Refine `HandleExplosionEvent` logic in `globals.lua` (e.g., check explosion types, distance).
*   Review `menudetection_detector.lua`. Consider adding checks for suspicious native calls often used by menus, beyond just keybinds.

### Resource Verification Logging (Guideline 30)
*   Enhance the `SYSTEM_RESOURCE_CHECK` handler in `server_main.lua` to provide more detailed logs when a mismatch occurs (e.g., clearly list mismatched resources).

## Phase 2: Data Handling, Actions, Refactoring

### Standardize Data & Storage (Guidelines 35, 36)
*   Review all `ProcessDetection` calls (server-side) and ensure `detectionData` is always a table with consistent fields where applicable.
*   Implement the `NexusGuardServer.Detections.Store` function in `globals.lua` to handle the standardized format for database logging.

### Enhance Player Metrics (Guideline 38)
*   In server-side handlers (`NEXUSGUARD_POSITION_UPDATE`, etc.), track player state (e.g., `isFalling`, `isInVehicle`) within `NexusGuardServer.PlayerMetrics` to provide context for checks.
*   **(Defer Guideline 37 - health source tracking - if damage event hooking was deferred)**.

### Refine Action System (Guidelines 42, 43, 44)
*   Review and refine the placeholder `IsConfirmedCheat` and `IsHighRisk` functions in `globals.lua`, ensuring they correctly utilize the `serverValidated` flag passed to `ProcessDetection`.
*   Make the trust score impact (`GetSeverity` function in `globals.lua`) more configurable, potentially adding options to `config.lua` for per-detection-type severity.
*   Implement progressive response logic within `ProcessDetection` (e.g., track confirmed flags in `PlayerMetrics` and issue harsher penalties for repeat offenses).

### Refine Ban System (Guidelines 39, 40, 41)
*   Verify the Unban command/functionality works correctly after async changes.
*   Add support for identifier-specific bans (e.g., ban license only) to `Bans.Store` and `Bans.Execute` in `globals.lua`, potentially adding a parameter or config option.
*   Improve ban message formatting in `Bans.Execute`.

### Code Refactoring (Guidelines 48, 49)
*   Break down the large `globals.lua` into smaller, focused server-side modules (e.g., `sv_bans.lua`, `sv_security.lua`, `sv_player_metrics.lua`, `sv_detections.lua`, `sv_discord.lua`). Update `fxmanifest.lua` and exports accordingly.
*   Move large event handler logic (like resource verification) from `server_main.lua` into functions within the new modules.

## Phase 3: Feature Enhancements & New Detections

### Implement Core Server-Side Detections (Guidelines 53, 56, 57)
*   Add server-side detection for spawning entities (vehicles, peds, objects) by hooking relevant events/natives if possible, comparing against thresholds in `config.lua`.
*   Add monitoring for abuse of specific sensitive network events (requires identifying target events).
*   Add server-side monitoring for players attempting to stop/start client resources after the initial check.

### Implement Key Server Authority Features (Guidelines 77, 78, 79)
*   Modify screenshot logic to be triggerable server-side based on confirmed flags/admin command.
*   Implement server-side weapon inventory tracking to validate ammo/weapon existence reports.
*   Implement damage event hooking for health validation if deferred earlier.

### Add Essential Admin Commands & Features (Guidelines 60, 61, 62)
*   Implement temporary bans (requires modifying `Bans.Store` and `Bans.IsPlayerBanned` to handle expiry).
*   Implement `/nexusguard_lookup [player_id]` command.
*   Implement `/nexusguard_clearwarnings [player_id]` command.

### Configuration & Logging Improvements (Guidelines 73, 74, 76)
*   Add comments to `config.lua` explaining default threshold choices.
*   Logically group related config options.
*   Implement config validation on startup (using `shared/config_validator.lua`).

### Add Other High-Value Detections/Features
*   Implement basic heuristics (Headshot rate, event frequency - Guidelines 51, 80).
*   Implement Spectate mode detection (Guideline 54).
*   Implement Player Report system command (`/report`) (Guideline 59).
*   Implement Ban list export/import features (Guidelines 66, 67).

## Phase 4: Testing, Usability, Documentation

### Testing (Guidelines 90-94)
*   Set up a testing framework (like Busted).
*   Write unit tests for key helper functions and modules.
*   Create specific test cases (`tools/test_cases.lua`) to trigger detections.

### Usability Improvements (Guidelines 95-97)
*   Improve formatting of admin notifications/chat messages.
*   Add command suggestions/autocomplete if possible.
*   Provide clearer feedback for admin actions.

### Documentation (Guidelines 81-89)
*   Create GitHub Wiki or documentation site structure.
*   Write detailed guides (Installation, Configuration, Tuning, Commands, Troubleshooting).
*   Add inline code comments (LuaDoc style).

### Final Cleanup & Release Prep (Guidelines 98-100)
*   Ensure all debug prints are removed or guarded by `Config.LogLevel`.
*   Add `CONTRIBUTING.md`.
*   Update version number and create release notes.

---
*This detailed plan prioritizes security and stability, then core features, followed by testing and documentation. Items like the full Discord bot, Admin Panel UI, and advanced detections (Lua injection, memory scanning) are treated as lower priority or separate future tasks.*
