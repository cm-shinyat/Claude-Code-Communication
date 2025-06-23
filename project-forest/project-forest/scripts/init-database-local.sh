#!/bin/bash

# Database initialization script for Project Forest
# This script can be run from any machine with network access to the RDS instance

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Project Forest Database Initialization${NC}"
echo "========================================"

# Database connection parameters
DB_HOST="project-forest-demo-db.cfmgmv0kqxfd.ap-northeast-1.rds.amazonaws.com"
DB_USER="admin"
DB_PASSWORD="BrSUaPbcXbLW4sB"
DB_NAME="projectforest"

echo -e "${YELLOW}Checking MySQL client...${NC}"
if ! command -v mysql &> /dev/null; then
    echo -e "${RED}MySQL client not found. Please install it first:${NC}"
    echo "  macOS: brew install mysql-client"
    echo "  Ubuntu/Debian: sudo apt-get install mysql-client"
    echo "  Amazon Linux: sudo yum install mysql"
    exit 1
fi

echo -e "${YELLOW}Testing database connection...${NC}"
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to database. Please check:${NC}"
    echo "  1. You have network access to RDS (VPN or bastion host)"
    echo "  2. Security group allows MySQL port (3306)"
    echo "  3. Database credentials are correct"
    exit 1
fi

echo -e "${GREEN}Successfully connected to database!${NC}"
echo -e "${YELLOW}Creating tables and inserting initial data...${NC}"

# Execute SQL commands
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
-- Characters table
CREATE TABLE IF NOT EXISTS characters (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  pronoun_first VARCHAR(100) DEFAULT '',
  pronoun_second VARCHAR(100) DEFAULT '', 
  face_graphic VARCHAR(255) DEFAULT '',
  description TEXT NOT NULL,
  traits TEXT DEFAULT '',
  favorites TEXT DEFAULT '',
  dislikes TEXT DEFAULT '',
  special_reactions TEXT DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tags table
CREATE TABLE IF NOT EXISTS tags (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  display_text VARCHAR(100) NOT NULL,
  icon VARCHAR(10) DEFAULT '🏷️',
  description TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Proper nouns table
CREATE TABLE IF NOT EXISTS proper_nouns (
  id INT AUTO_INCREMENT PRIMARY KEY,
  word VARCHAR(200) NOT NULL,
  reading VARCHAR(200),
  category VARCHAR(100) DEFAULT 'その他',
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_word (word)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Forbidden words table
CREATE TABLE IF NOT EXISTS forbidden_words (
  id INT AUTO_INCREMENT PRIMARY KEY,
  word VARCHAR(200) NOT NULL,
  category VARCHAR(100) DEFAULT 'その他',
  severity ENUM('低', '中', '高') DEFAULT '中',
  reason TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_word (word)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Styles table
CREATE TABLE IF NOT EXISTS styles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  font VARCHAR(100) DEFAULT '',
  max_chars INT DEFAULT NULL,
  max_lines INT DEFAULT NULL,
  font_size INT DEFAULT NULL,
  auto_format_rules TEXT DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert initial characters
INSERT IGNORE INTO characters (name, pronoun_first, pronoun_second, face_graphic, description, traits, favorites, dislikes, special_reactions) VALUES
('protagonist', '俺', '俺', '', 'メインキャラクター。物語の主人公として登場します。', 'リーダーシップ、決断力', '冒険、仲間', '嘘、裏切り', '怒ると手がつけられない'),
('mentor', '私', '私', '', '主人公を導く指導者的な役割のキャラクター。', '知識豊富、冷静', '読書、お茶', '騒音、無礼な態度', '真実を隠すときは目を逸らす'),
('rival', '僕', '僕', '', '主人公と対立する立場のキャラクター。', 'プライド高い、負けず嫌い', '勝負、称賛', '負けること、無視されること', '敗北すると悔し涙を流す'),
('supporter', 'あたし', 'あたし', '', '主人公を支援する味方キャラクター。', '優しい、献身的', '料理、花', '争い、悲しみ', '嬉しいと飛び跳ねる');

-- Insert initial tags
INSERT IGNORE INTO tags (name, display_text, icon, description) VALUES
('character_name', '{CHARACTER_NAME}', '👤', 'キャラクター名を動的に表示するタグ'),
('location', '{LOCATION}', '📍', '場所名を動的に表示するタグ'),
('date', '{DATE}', '📅', '日付を動的に表示するタグ'),
('time', '{TIME}', '⏰', '時刻を動的に表示するタグ'),
('weather', '{WEATHER}', '🌤️', '天気を動的に表示するタグ');

-- Insert initial proper nouns
INSERT IGNORE INTO proper_nouns (word, reading, category, description) VALUES
('東京', 'トウキョウ', '地名', '日本の首都'),
('大阪', 'オオサカ', '地名', '関西の主要都市'),
('Apple', 'アップル', '企業名', 'アメリカのテクノロジー企業'),
('Google', 'グーグル', '企業名', 'アメリカの検索エンジン企業'),
('PlayStation', 'プレイステーション', '商品名', 'ソニーのゲーム機');

-- Insert initial forbidden words
INSERT IGNORE INTO forbidden_words (word, category, severity, reason) VALUES
('バカ', '侮辱的表現', '中', '他者を侮辱する可能性がある表現'),
('アホ', '侮辱的表現', '中', '他者を侮辱する可能性がある表現'),
('死ね', '暴力的表現', '高', '暴力的で攻撃的な表現'),
('殺す', '暴力的表現', '高', '暴力的で危険な表現');

-- Insert initial styles
INSERT IGNORE INTO styles (name, font, max_chars, max_lines, font_size, auto_format_rules) VALUES
('デフォルト', 'Noto Sans JP', 1000, 50, 14, ''),
('小説スタイル', 'Times New Roman', 2000, 100, 12, '段落間に空行を挿入'),
('ブログスタイル', 'Arial', 1500, 75, 16, '見出しを自動生成'),
('レポートスタイル', 'Meiryo', 3000, 150, 11, '箇条書きを自動整形');

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_characters_name ON characters(name);
CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);
CREATE INDEX IF NOT EXISTS idx_proper_nouns_word ON proper_nouns(word);
CREATE INDEX IF NOT EXISTS idx_forbidden_words_word ON forbidden_words(word);
CREATE INDEX IF NOT EXISTS idx_styles_name ON styles(name);
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Database initialization completed successfully!${NC}"
    echo ""
    echo "Verifying table creation..."
    
    # Show table counts
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
SELECT 'characters' as table_name, COUNT(*) as count FROM characters
UNION ALL
SELECT 'tags', COUNT(*) FROM tags
UNION ALL
SELECT 'proper_nouns', COUNT(*) FROM proper_nouns
UNION ALL
SELECT 'forbidden_words', COUNT(*) FROM forbidden_words
UNION ALL
SELECT 'styles', COUNT(*) FROM styles;
EOF
    
    echo ""
    echo -e "${GREEN}✓ Database is ready for use!${NC}"
    echo "You can now access the admin panel at your ECS application URL."
else
    echo -e "${RED}Database initialization failed!${NC}"
    exit 1
fi