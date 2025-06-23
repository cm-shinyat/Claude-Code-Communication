#!/bin/bash

# データベース初期化用踏み台サーバー作成スクリプト
# 実行前に適切なAWSアカウント（388450459156）にスイッチしてください

set -e

echo "🚀 Project Forest データベース初期化用踏み台サーバーを作成します"
echo "============================================================="

# 設定
KEY_NAME="bastion-mysql-client-key"
INSTANCE_TYPE="t3.micro"
AMI_NAME="al2023-ami-*"
SECURITY_GROUP_NAME="bastion-mysql-client-sg"
TAG_NAME="bastion-mysql-client"

# 1. デフォルトVPCの取得
echo "📍 デフォルトVPCを取得中..."
VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region ap-northeast-1)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  echo "❌ デフォルトVPCが見つかりません"
  exit 1
fi

echo "✅ VPC ID: $VPC_ID"

# 2. サブネットの取得
echo "📍 パブリックサブネットを取得中..."
SUBNET_ID=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --region ap-northeast-1)

echo "✅ Subnet ID: $SUBNET_ID"

# 3. AMI IDの取得
echo "📍 Amazon Linux 2023 AMIを取得中..."
AMI_ID=$(aws-vault exec shinyat -- aws ec2 describe-images \
  --filters "Name=name,Values=$AMI_NAME" "Name=owner-alias,Values=amazon" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text \
  --region ap-northeast-1)

echo "✅ AMI ID: $AMI_ID"

# 4. キーペアの作成
echo "🔑 SSHキーペアを作成中..."
if ! aws-vault exec shinyat -- aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region ap-northeast-1 >/dev/null 2>&1; then
  aws-vault exec shinyat -- aws ec2 import-key-pair \
    --key-name "$KEY_NAME" \
    --public-key-material fileb://$HOME/.ssh/id_rsa.pub \
    --region ap-northeast-1
  echo "✅ キーペア '$KEY_NAME' を作成しました"
else
  echo "✅ キーペア '$KEY_NAME' は既に存在します"
fi

# 5. セキュリティグループの作成
echo "🛡️ セキュリティグループを作成中..."
SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name "$SECURITY_GROUP_NAME" \
  --description "Bastion server for MySQL client access" \
  --vpc-id "$VPC_ID" \
  --region ap-northeast-1 \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws-vault exec shinyat -- aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region ap-northeast-1)

echo "✅ Security Group ID: $SG_ID"

# 6. セキュリティグループルールの追加
echo "🛡️ セキュリティグループルールを設定中..."
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-1 2>/dev/null || echo "SSH rule already exists"

# 7. ユーザーデータの準備
USER_DATA=$(cat << 'EOF' | base64
#!/bin/bash
yum update -y
yum install -y mysql

# データベース初期化スクリプトの作成
cat > /home/ec2-user/init-database.sh << 'SCRIPT_EOF'
#!/bin/bash

echo "🗄️ Project Forest データベース初期化開始..."
echo "============================================="

DB_HOST="project-forest-demo-db.cfmgmv0kqxfd.ap-northeast-1.rds.amazonaws.com"
DB_USER="admin"
DB_PASSWORD="BrSUaPbcXbLW4sB"
DB_NAME="projectforest"

# 接続テスト
echo "📡 データベース接続をテスト中..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ データベースに接続できません"
    echo "RDSのセキュリティグループでこのインスタンスからのアクセスを許可してください"
    exit 1
fi

echo "✅ データベース接続成功！"
echo "🏗️ テーブルを作成中..."

mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'SQL_EOF'
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

INSERT IGNORE INTO characters (name, pronoun_first, pronoun_second, face_graphic, description, traits, favorites, dislikes, special_reactions) VALUES
('protagonist', '俺', '俺', '', 'メインキャラクター。物語の主人公として登場します。', 'リーダーシップ、決断力', '冒険、仲間', '嘘、裏切り', '怒ると手がつけられない'),
('mentor', '私', '私', '', '主人公を導く指導者的な役割のキャラクター。', '知識豊富、冷静', '読書、お茶', '騒音、無礼な態度', '真実を隠すときは目を逸らす'),
('rival', '僕', '僕', '', '主人公と対立する立場のキャラクター。', 'プライド高い、負けず嫌い', '勝負、称賛', '負けること、無視されること', '敗北すると悔し涙を流す'),
('supporter', 'あたし', 'あたし', '', '主人公を支援する味方キャラクター。', '優しい、献身的', '料理、花', '争い、悲しみ', '嬉しいと飛び跳ねる');

INSERT IGNORE INTO tags (name, display_text, icon, description) VALUES
('character_name', '{CHARACTER_NAME}', '👤', 'キャラクター名を動的に表示するタグ'),
('location', '{LOCATION}', '📍', '場所名を動的に表示するタグ'),
('date', '{DATE}', '📅', '日付を動的に表示するタグ'),
('time', '{TIME}', '⏰', '時刻を動的に表示するタグ'),
('weather', '{WEATHER}', '🌤️', '天気を動的に表示するタグ');

INSERT IGNORE INTO proper_nouns (word, reading, category, description) VALUES
('東京', 'トウキョウ', '地名', '日本の首都'),
('大阪', 'オオサカ', '地名', '関西の主要都市'),
('Apple', 'アップル', '企業名', 'アメリカのテクノロジー企業'),
('Google', 'グーグル', '企業名', 'アメリカの検索エンジン企業'),
('PlayStation', 'プレイステーション', '商品名', 'ソニーのゲーム機');

INSERT IGNORE INTO forbidden_words (word, category, severity, reason) VALUES
('バカ', '侮辱的表現', '中', '他者を侮辱する可能性がある表現'),
('アホ', '侮辱的表現', '中', '他者を侮辱する可能性がある表現'),
('死ね', '暴力的表現', '高', '暴力的で攻撃的な表現'),
('殺す', '暴力的表現', '高', '暴力的で危険な表現');

INSERT IGNORE INTO styles (name, font, max_chars, max_lines, font_size, auto_format_rules) VALUES
('デフォルト', 'Noto Sans JP', 1000, 50, 14, ''),
('小説スタイル', 'Times New Roman', 2000, 100, 12, '段落間に空行を挿入'),
('ブログスタイル', 'Arial', 1500, 75, 16, '見出しを自動生成'),
('レポートスタイル', 'Meiryo', 3000, 150, 11, '箇条書きを自動整形');

CREATE INDEX IF NOT EXISTS idx_characters_name ON characters(name);
CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);
CREATE INDEX IF NOT EXISTS idx_proper_nouns_word ON proper_nouns(word);
CREATE INDEX IF NOT EXISTS idx_forbidden_words_word ON forbidden_words(word);
CREATE INDEX IF NOT EXISTS idx_styles_name ON styles(name);

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
    echo "✅ データベース初期化完了！"
    echo ""
    echo "🎉 Project Forestデータベースの準備ができました"
    echo "管理画面でデータの確認ができます"
else
    echo "❌ データベース初期化に失敗しました"
    exit 1
fi
SCRIPT_EOF

chmod +x /home/ec2-user/init-database.sh
chown ec2-user:ec2-user /home/ec2-user/init-database.sh

echo "✅ 踏み台サーバーのセットアップ完了"
echo "データベース初期化は './init-database.sh' を実行してください"
EOF
)

# 8. EC2インスタンスの起動
echo "🚀 EC2インスタンスを起動中..."
INSTANCE_ID=$(aws-vault exec shinyat -- aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --user-data "$USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$TAG_NAME},{Key=Purpose,Value=Database-Init}]" \
  --region ap-northeast-1 \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "✅ インスタンス ID: $INSTANCE_ID"

# 9. パブリックIPの取得
echo "⏳ インスタンスの起動を待機中..."
aws-vault exec shinyat -- aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region ap-northeast-1

PUBLIC_IP=$(aws-vault exec shinyat -- aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region ap-northeast-1)

echo ""
echo "🎉 踏み台サーバーの作成完了！"
echo "================================"
echo "インスタンス ID: $INSTANCE_ID"
echo "パブリック IP: $PUBLIC_IP"
echo ""
echo "📋 次の手順:"
echo "1. RDSセキュリティグループにこのインスタンスからのアクセスを許可:"
echo "   セキュリティグループ ID: $SG_ID"
echo ""
echo "2. SSHで接続:"
echo "   ssh -i ~/.ssh/id_rsa ec2-user@$PUBLIC_IP"
echo ""
echo "3. データベース初期化を実行:"
echo "   ./init-database.sh"
echo ""
echo "⚠️ 初期化完了後はインスタンスを削除してください:"
echo "   aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region ap-northeast-1"