#!/bin/bash

# Update system and install MySQL client
yum update -y
yum install -y mysql

# Create database initialization script
cat > /home/ec2-user/init-database.sh << 'SCRIPT_EOF'
#!/bin/bash

echo "Initializing Project Forest Database..."
echo "======================================="

# Database connection parameters
DB_HOST="${db_host}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
DB_NAME="${db_name}"

# Test connection first
echo "Testing database connection..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to connect to database!"
    exit 1
fi

echo "Connected successfully! Initializing schema..."

# Execute database initialization
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'SQL_EOF'
-- Project Forest Database Initialization
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

-- Show results
SHOW TABLES;
SELECT 'Characters' as table_name, COUNT(*) as count FROM characters
UNION ALL
SELECT 'Tags', COUNT(*) FROM tags
UNION ALL
SELECT 'Proper Nouns', COUNT(*) FROM proper_nouns
UNION ALL
SELECT 'Forbidden Words', COUNT(*) FROM forbidden_words
UNION ALL
SELECT 'Styles', COUNT(*) FROM styles;
SQL_EOF

if [ $? -eq 0 ]; then
    echo "✅ Database initialization completed successfully!"
    echo ""
    echo "Your Project Forest database is now ready to use."
    echo "You can access the admin panel at your ECS application URL."
else
    echo "❌ Database initialization failed!"
    exit 1
fi
SCRIPT_EOF

# Make the script executable and set proper ownership
chmod +x /home/ec2-user/init-database.sh
chown ec2-user:ec2-user /home/ec2-user/init-database.sh

# Create a simple status check script
cat > /home/ec2-user/check-db.sh << 'CHECK_EOF'
#!/bin/bash
mysql -h ${db_host} -u ${db_user} -p${db_password} ${db_name} -e "
SHOW TABLES;
SELECT COUNT(*) as character_count FROM characters;
"
CHECK_EOF

chmod +x /home/ec2-user/check-db.sh
chown ec2-user:ec2-user /home/ec2-user/check-db.sh

echo "Bastion server setup completed. Run './init-database.sh' to initialize the database."