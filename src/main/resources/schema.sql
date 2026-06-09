-- ============================================================================
-- Workshop Registration Schema
-- Run this once on your MySQL server before deploying the WAR.
--
--   mysql -h <DB_HOST> -u <DB_USER> -p < schema.sql
-- ============================================================================

CREATE DATABASE IF NOT EXISTS workshop_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE workshop_db;

CREATE TABLE IF NOT EXISTS registrations (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    student_name    VARCHAR(120) NOT NULL,
    student_no      VARCHAR(40)  NOT NULL,
    workshop        VARCHAR(100) DEFAULT NULL,
    registered_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_student_workshop (student_no, workshop),
    KEY idx_registered_at (registered_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
