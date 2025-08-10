# NexusGuard - Modular FiveM Anti-Cheat Framework

NexusGuard is a modular, event-driven anti-cheat framework designed for FiveM servers. It provides a core structure and detection modules that can be customized and extended by server developers.

**⚠️ This is a framework resource for FiveM servers, not a standalone solution. ⚠️** It requires proper configuration and integration with your server's existing systems (permissions, bans, database) to function effectively.

## Features (Core Framework)

*   **Modular Detector System**: Easily enable, disable, or create custom detection modules (`client/detectors/`).
*   **Event-Driven Architecture**: Uses standardized events for communication via `shared/event_registry.lua`.
*   **Client & Server Logic**: Basic separation of client-side checks and server-side validation/actions.
*   **Configuration**: Extensive configuration options via `config.lua`.
*   **Secure Token System**: Includes HMAC-SHA256 tokens with anti-replay protection.
*   **Basic Detections Included**: Examples for God Mode, Speed Hack, NoClip, Teleport, Weapon Mods, Resource Monitoring, Menu Keybinds.
*   **Helper Utilities**: Basic logging, database-driven ban system (requires setup), admin notifications.
*   **Discord Integration**: Basic webhook logging and Rich Presence support.
*   **Database Support**: Includes schema (`sql/schema.sql`) for storing bans, detections, and session summaries using `oxmysql` (via `server/sv_database.lua`).
*   **Dependency Management**: Robust dependency detection and version validation with fallbacks for missing dependencies.
*   **FiveM Natives Wrapper**: Safe wrapper for FiveM natives with error handling and consistent behavior across environments.
*   **Server Authority**: Enhanced server-side validation for player health, position, and damage events.

## Dependencies

**Required:**

*   **[oxmysql](https://github.com/overextended/oxmysql)**: Required for database features (bans, detections, sessions) if `Config.Database.enabled = true`. Also provides the necessary JSON library. **Must be started before NexusGuard.**
*   **[screenshot-basic](https://github.com/citizenfx/screenshot-basic)**: Required for the screenshot functionality if `Config.ScreenCapture.enabled = true`. **Must be started before NexusGuard.**
*   **[ox_lib](https://github.com/overextended/ox_lib)**: Required for the default secure token implementation (HMAC-SHA256 via `lib.crypto`) and potentially other utilities. **Must be started before NexusGuard.**

**Optional:**

*   **`chat` resource**: Recommended for displaying client-side warnings via the `NexusGuard:CheatWarning` event. If not used, warnings will only appear in the F8 console.
*   **Framework for Permissions (ESX/QBCore)**: If you set `Config.PermissionsFramework` to `"esx"` or `"qbcore"`, the corresponding framework (`es_extended` or `qb-core`) must be running and started *before* NexusGuard for admin checks to function correctly.
*   **External Discord Bot**: If using advanced Discord bot features (commands, player reports beyond webhooks) defined in `config.lua`, a separate bot implementation (e.g., using discord.js, discord.py, etc.) interacting with NexusGuard (potentially via custom events or API calls) is required. This framework only provides basic webhook logging and Rich Presence.

## Installation

1.  **Download:** Download the latest release (v0.7.0) of NexusGuard.
2.  **Extract:** Extract the `nexus-guard` (or similarly named) folder into your server's `resources` directory. Rename it to `NexusGuard` if desired.
3.  **Dependencies:** Ensure **`oxmysql`**, **`screenshot-basic`**, and **`ox_lib`** are installed and listed in your `server.cfg` to start *before* NexusGuard. Install optional dependencies (like `chat`, `es_extended`, `qb-core`) as needed based on your `config.lua` settings.
4.  **Database Setup:**
    *   Ensure you have a MySQL database server accessible by your FiveM server.
    *   Import the `sql/schema.sql` file (located inside the NexusGuard resource folder) into your database. This will create the necessary tables (`nexusguard_bans`, `nexusguard_detections`, `nexusguard_sessions`).
    *   Ensure your `oxmysql` resource is correctly configured to connect to your database.
5.  **Configure `config.lua`:**
    *   Carefully review **all** options in `config.lua`. Pay close attention to comments indicating required fields or critical settings.
    *   **CRITICAL:** Set `Config.SecuritySecret` to a **long, unique, and random string**. This secret is used by the default secure token implementation (HMAC-SHA256). **Do not leave the default value or share it.**
    *   **Set `Config.PermissionsFramework`:** Choose `"ace"`, `"esx"`, `"qbcore"`, or `"custom"` based on your server's permission system. See comments in `config.lua`.
    *   **Configure `Config.AdminGroups`:** List the group/permission names that should be considered admin *according to the framework selected above*. (e.g., for ACE: `"admin"`, `"superadmin"`; for ESX: `"admin"`, `"superadmin"`; for QBCore: `"admin"`, `"god"`, etc.).
    *   Fill in required URLs/IDs if features are enabled: `Config.DiscordWebhook` (for general logs), specific webhook URLs in `Config.Discord.webhooks` (optional), `Config.ScreenCapture.webhookURL`, `Config.Discord.RichPresence.AppId`.
    *   If enabling `Config.Features.resourceVerification`, carefully configure the `whitelist` or `blacklist`. **Whitelist mode requires adding ALL essential server resources (framework, maps, scripts) to prevent false kicks/bans.** See comments in `config.lua`.
    *   Adjust detection thresholds (`Config.Thresholds`) and enable/disable detectors (`Config.Detectors`) based on testing and server needs.
6.  **Implement Custom Logic (If Needed):**
    *   **Custom Permissions:** If you set `Config.PermissionsFramework = "custom"`, you **MUST** edit the `IsPlayerAdmin` function in `globals.lua` to add your specific permission checking logic.
    *   **(Optional) Placeholders:** Review functions marked as placeholders in the code (search for comments like `-- Placeholder:`) and implement them if you intend to use those features.
7.  **Server Config:** Add `ensure NexusGuard` to your `server.cfg`, ensuring it starts *after* its required dependencies (`oxmysql`, `screenshot-basic`, `ox_lib`) and any selected optional framework dependencies (`es_extended`, `qb-core`).
8.  **Restart Server & Test:** Restart your FiveM server. Check the console thoroughly for any NexusGuard errors or warnings (especially critical ones about missing dependencies or security). Test detections and actions rigorously, paying close attention to admin checks.

## Configuration Deep Dive

*   **`config.lua`**: Contains all user-configurable settings. Read the comments carefully.
*   **`Config.SecuritySecret`**: **MUST BE CHANGED** to a strong, unique secret. This is used by the default secure token system.
*   **Security Implementation**: A default secure token system using HMAC-SHA256 (via `ox_lib`) with built-in anti-replay protection is now included. Ensure `ox_lib` is installed and `Config.SecuritySecret` is set correctly.
*   **Permissions**: Configure `Config.PermissionsFramework` and `Config.AdminGroups` in `config.lua`. You only need to edit `globals.lua` if using the `"custom"` framework setting.
*   **Resource Verification**: The logic is implemented, but if enabled, the `whitelist` or `blacklist` in `config.lua` **MUST BE CONFIGURED ACCURATELY**. Whitelist mode is dangerous if not all required resources are listed.
*   **Thresholds**: Tune detection thresholds (`Config.Thresholds`) carefully through testing.
*   **Detectors**: Enable/disable specific detectors (`Config.Detectors`).
*   **Actions**: Configure reactions (`Config.Actions`).
*   **Dependency Management**: The framework now includes robust dependency detection and version validation. See `docs/dependency_manager.md` for details.
*   **Documentation**: Detailed documentation is available in the `docs/` directory, including guides for creating custom detectors, configuring the framework, and understanding core modules.

## Adding Custom Detectors

1.  Create a new Lua file in `client/detectors/`.
2.  Follow the structure of `client/detectors/detector_template.lua`.
3.  Define a unique `DetectorName` string variable within your new detector file. This name will be used as the key in `Config.Detectors` (in `config.lua`) to enable/disable it.
4.  Implement the `Detector.Initialize(nexusGuardInstance, eventRegistry)` function. This function receives the core NexusGuard instance and the EventRegistry. Store the `nexusGuardInstance` locally (e.g., `self.NexusGuard = nexusGuardInstance`) if you need to access its functions (like `ReportCheat`) later. Use this function for any setup or configuration reading.
5.  Implement the `Detector.Check()` function with your detection logic. Use the stored instance to report violations (e.g., `self.NexusGuard:ReportCheat(DetectorName, details)`). This handles the warning system and triggers the server event.
6.  The registration block at the end (using `DetectorRegistry.Register`) will automatically register and start your detector if `Config.Detectors[DetectorName]` is set to `true`.

## Common Issues & Troubleshooting

*   **CRITICAL: `Config.SecuritySecret` Error / Invalid Token Errors:**
    *   **Cause:** You haven't changed `Config.SecuritySecret` in `config.lua` from the default value, or `ox_lib` is not started *before* NexusGuard.
    *   **Solution:**
        1.  **STOP YOUR SERVER.**
        2.  Open `config.lua` and set `Config.SecuritySecret` to a **long, unique, random string** (e.g., use a password generator). **DO NOT SHARE THIS SECRET.**
        3.  Ensure `ensure ox_lib` is listed **before** `ensure NexusGuard` in your `server.cfg`.
        4.  Restart your server.

*   **`ox_lib` Crypto Errors / Security Token System Disabled:**
    *   **Cause:** `ox_lib` is not started before NexusGuard, is outdated, or its crypto module failed to load.
    *   **Solution:**
        1.  Ensure `ensure ox_lib` is listed **before** `ensure NexusGuard` in your `server.cfg`.
        2.  Update `ox_lib` to its latest version.
        3.  Check the server console during startup for any errors specifically from `ox_lib`.
        4.  Restart your server.

*   **Players Kicked/Banned Incorrectly by Resource Verification:**
    *   **Cause:** If using `Config.Features.resourceVerification.mode = "whitelist"`, you haven't added all essential server resources to the `whitelist` table in `config.lua`.
    *   **Solution:**
        1.  Temporarily set `Config.Features.resourceVerification.enabled = false` in `config.lua` to stop the kicks/bans.
        2.  Restart NexusGuard (`restart NexusGuard`).
        3.  As an admin in-game, run the command `/nexusguard_getresources`.
        4.  Copy the entire list printed in your chat (including the `{` and `}` braces).
        5.  Paste this list into the `Config.Features.resourceVerification.whitelist` table in `config.lua`, replacing the default example list.
        6.  Review the pasted list and remove any non-essential or temporary resources if desired.
        7.  Set `Config.Features.resourceVerification.enabled = true` again.
        8.  Restart NexusGuard (`restart NexusGuard`).

*   **Admin Commands Don't Work / Not Detected as Admin:**
    *   **Cause:** `Config.PermissionsFramework` is not set correctly, `Config.AdminGroups` doesn't match your framework's groups, or the required framework (ESX/QBCore) isn't started before NexusGuard.
    *   **Solution:**
        1.  **Verify `Config.PermissionsFramework`:** Open `config.lua` and ensure `Config.PermissionsFramework` is set to `"ace"`, `"esx"`, or `"qbcore"` to match your server setup. If you have custom permission logic, set it to `"custom"` and implement it in `globals.lua`.
        2.  **Verify `Config.AdminGroups`:** Ensure this table in `config.lua` contains the *exact* group names (case-sensitive!) that signify admin privileges in your framework.
            *   **ACE:** Check your `server.cfg` for `add_principal identifier.license:<your_license> group.admin` (or similar group name). The group name here must be in `Config.AdminGroups`.
            *   **ESX:** Check your `users` and `groups` tables in the database. Find your user record and see which group they belong to (e.g., `superadmin`, `admin`). That group name must be in `Config.AdminGroups`.
            *   **QBCore:** Check your framework's permission setup (often in `shared/permissions.lua` or similar within `qb-core`). Identify the highest permission group(s) (e.g., `god`, `admin`) and ensure they are listed in `Config.AdminGroups`.
        3.  **Check Resource Start Order:** If using `"esx"` or `"qbcore"`, ensure `ensure es_extended` or `ensure qb-core` is listed **before** `ensure NexusGuard` in your `server.cfg`. The framework needs to load first.
        4.  **Restart & Test:** After making changes, restart your server and test admin commands again.

*   **Database Errors (Connection, Schema):**
    *   **Cause:** `oxmysql` is not configured correctly, not started before NexusGuard, or the database schema wasn't imported.
    *   **Solution:**
        1.  Ensure `oxmysql` is installed and configured with your correct database credentials.
        2.  Ensure `ensure oxmysql` is listed **before** `ensure NexusGuard` in your `server.cfg`.
        3.  Verify you imported `NexusGuard/sql/schema.sql` into your database. Check the server console for specific MySQL errors during startup.

*   **Screenshot Errors:**
    *   **Cause:** `screenshot-basic` resource is missing or not started before NexusGuard, or `Config.ScreenCapture.webhookURL` is incorrect or missing.
    *   **Solution:**
        1.  Ensure `screenshot-basic` is installed.
        2.  Ensure `ensure screenshot-basic` is listed **before** `ensure NexusGuard` in your `server.cfg`.
        3.  Verify `Config.ScreenCapture.webhookURL` in `config.lua` is a valid Discord webhook URL.

*   **False Positives (Speed, Teleport, etc.):**
    *   **Cause:** Default thresholds in `Config.Thresholds` might be too strict for your server or specific situations (e.g., custom vehicles, specific framework teleports).
    *   **Solution:** Gradually increase the relevant threshold values in `Config.Thresholds` (e.g., `speedHackMultiplier`, `teleportDistance`) and test thoroughly. Monitor server console logs for detection messages to identify patterns.

*   **"[NexusGuard] CRITICAL: EventRegistry not found..." Error:**
    *   **Cause:** The essential `shared/event_registry.lua` script is not being loaded correctly, likely due to an issue in `fxmanifest.lua`.
    *   **Solution:** Ensure `shared/event_registry.lua` exists and is correctly listed under `shared_scripts` in your `fxmanifest.lua`. Verify the file path and name are accurate.

## API / Exports

NexusGuard exports a server-side API table defined in `globals.lua`.

```lua
-- Example Usage from another server-side script:
local NexusGuardAPI = exports['NexusGuard']:GetNexusGuardServerAPI()

if NexusGuardAPI then
    -- Check if a function exists before calling (good practice)
    if NexusGuardAPI.IsPlayerAdmin then
        local isAdmin = NexusGuardAPI.IsPlayerAdmin(source) -- 'source' is the player's server ID
        print(('[Example] Player %s admin status: %s'):format(source, tostring(isAdmin)))
    end

    -- Example: Triggering a manual detection report (if you implement such a function)
    -- if NexusGuardAPI.ReportManualDetection then
    --     NexusGuardAPI.ReportManualDetection(adminSource, targetSource, "Manual observation: Suspicious behavior")
    -- end
end
```

*Note: Review the `NexusGuardServerAPI` table definition at the bottom of `globals.lua` to see available functions. Add functions there as needed, ensuring they are secure and well-documented.*

## Contribution

Contributions are welcome! Please follow these guidelines:

1.  **Fork** the repository.
2.  Create a new **branch** for your feature or bug fix (`git checkout -b feature/your-feature-name`).
3.  Write **clear and concise** code with comments.
4.  Ensure your changes **do not break** existing functionality.
5.  Test your changes thoroughly.
6.  Submit a **Pull Request** with a detailed description of your changes.

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.
