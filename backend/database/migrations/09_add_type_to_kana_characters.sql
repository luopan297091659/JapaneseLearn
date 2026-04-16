-- Migration: Add type field to kana_characters table
-- Date: 2026-04-06
-- Purpose: Add type field to distinguish between normal, dakuten, handakuten, and youon characters

USE japanese_learn;

-- Add the type column if it doesn't exist
ALTER TABLE kana_characters 
ADD COLUMN type ENUM('normal','dakuten','handakuten','youon') NOT NULL DEFAULT 'normal' 
COMMENT '字符类型: normal(基本), dakuten(浓音), handakuten(半浊音), youon(拗音)' 
AFTER romaji;

-- Create index for type field
CREATE INDEX IF NOT EXISTS idx_type ON kana_characters(type);

-- Update existing data based on category_id to set proper type values
-- Category 1: Hiragana - normal
-- Category 2: Katakana - normal
-- Category 3: Dakuten - dakuten
-- Category 4: Handakuten - handakuten
-- Category 5: Youon - youon

UPDATE kana_characters SET type='normal' WHERE category_id IN (1, 2);
UPDATE kana_characters SET type='dakuten' WHERE category_id = 3;
UPDATE kana_characters SET type='handakuten' WHERE category_id = 4;
UPDATE kana_characters SET type='youon' WHERE category_id = 5;

-- Verify the migration
SELECT type, COUNT(*) as count FROM kana_characters GROUP BY type;
