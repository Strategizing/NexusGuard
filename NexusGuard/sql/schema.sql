-- NexusGuard Database Schema (MySQL)

-- Bans Table
CREATE TABLE IF NOT EXISTS `nexusguard_bans` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(255) DEFAULT NULL,
  `license` VARCHAR(255) DEFAULT NULL,
  `ip` VARCHAR(45) DEFAULT NULL,
  `discord` VARCHAR(255) DEFAULT NULL,
  `reason` TEXT DEFAULT NULL,
  `admin` VARCHAR(255) DEFAULT NULL,
  `ban_date` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `expire_date` TIMESTAMP NULL DEFAULT NULL, -- For temporary bans
  INDEX `license_index` (`license`),
  INDEX `ip_index` (`ip`),
  INDEX `discord_index` (`discord`),
  INDEX `expire_index` (`expire_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Detections History Table
CREATE TABLE IF NOT EXISTS `nexusguard_detections` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `player_name` VARCHAR(255) DEFAULT NULL,
  `player_license` VARCHAR(255) DEFAULT NULL,
  `player_ip` VARCHAR(45) DEFAULT NULL,
  `detection_type` VARCHAR(100) NOT NULL,
  `detection_data` JSON DEFAULT NULL,
  `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `player_license_index` (`player_license`),
  INDEX `detection_type_index` (`detection_type`),
  INDEX `timestamp_index` (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Player Sessions/Metrics Summary Table (Optional but useful)
-- Stores summary data when a player disconnects
CREATE TABLE IF NOT EXISTS `nexusguard_sessions` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `player_name` VARCHAR(255) DEFAULT NULL,
  `player_license` VARCHAR(255) NOT NULL,
  `connect_time` TIMESTAMP NULL DEFAULT NULL,
  `disconnect_time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `play_time_seconds` INT DEFAULT 0,
  `final_trust_score` FLOAT DEFAULT 100.0,
  `total_detections` INT DEFAULT 0,
  `total_warnings` INT DEFAULT 0,
  INDEX `player_license_index` (`player_license`),
  INDEX `disconnect_time_index` (`disconnect_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
