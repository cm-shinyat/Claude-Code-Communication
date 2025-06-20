# ローカル開発環境セットアップガイド

Project Forest のローカル開発環境を最速でセットアップするためのガイドです。

## 🎯 概要

このガイドでは、開発者が Project Forest を素早くローカルで起動できるように、シンプルで効率的なセットアップ手順を提供します。

## 📋 前提条件

### 必須ツール

- **Node.js 18以上** - [公式サイト](https://nodejs.org/)からダウンロード
- **MySQL 8.0以上** - [公式サイト](https://dev.mysql.com/downloads/)からダウンロード
- **Git** - [公式サイト](https://git-scm.com/)からダウンロード

### 推奨ツール

- **VS Code** - エディタ
- **Docker Desktop** - コンテナ環境（オプション）
- **Postman** - API テスト用

## 🚀 クイックスタート（5分セットアップ）

### 1. リポジトリクローンと依存関係インストール

```bash
# プロジェクトをクローン
git clone https://github.com/your-org/project-forest.git
cd project-forest

# 依存関係をインストール
npm install
```

### 2. 自動セットアップ実行

```bash
# 全自動セットアップ（推奨）
./infrastructure/scripts/setup-local.sh

# または Docker を使用
./docs/development/scripts/setup-docker.sh
```

**セットアップが完了したら：**
- ブラウザで http://localhost:3000 にアクセス
- 管理者アカウント：`admin@example.com` / `password`

## 📝 手動セットアップ（詳細手順）

自動セットアップがうまくいかない場合の手動手順です。

### 1. 環境設定ファイル作成

```bash
# 環境設定ファイル作成
cp .env.example .env.local
```

**.env.local の設定例:**
```bash
# データベース設定
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=password
DB_NAME=project_forest_dev

# アプリケーション設定
NODE_ENV=development
APP_PORT=3000
APP_HOST=localhost

# 認証設定
JWT_SECRET=your-development-jwt-secret-key
SESSION_SECRET=your-development-session-secret

# 機能フラグ
ENABLE_TRANSLATION_API=false
ENABLE_CSV_IMPORT=true
ENABLE_WEBSOCKETS=true
ENABLE_AUDIT_LOG=true

# ログ設定
LOG_LEVEL=debug
LOG_FORMAT=pretty

# ファイルアップロード
MAX_FILE_SIZE=10485760
UPLOAD_DIR=./uploads
```

### 2. データベースセットアップ

#### MySQL を直接使用する場合

```bash
# MySQL サービス開始
sudo systemctl start mysql  # Linux
brew services start mysql   # macOS

# データベース作成
mysql -u root -p -e "CREATE DATABASE project_forest_dev CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# スキーマ適用
mysql -u root -p project_forest_dev < database/schema.sql
```

#### Docker を使用する場合

```bash
# MySQL コンテナ起動
docker run --name project-forest-mysql \
  -e MYSQL_ROOT_PASSWORD=password \
  -e MYSQL_DATABASE=project_forest_dev \
  -p 3306:3306 \
  -d mysql:8.0

# コンテナ起動確認
docker ps

# スキーマ適用
docker exec -i project-forest-mysql mysql -u root -ppassword project_forest_dev < database/schema.sql
```

### 3. サンプルデータ投入

```bash
# サンプルデータ作成スクリプト実行
./docs/development/scripts/seed-data.sh

# または手動でサンプルユーザー作成
node ./docs/development/scripts/create-users.js
```

### 4. アプリケーション起動

```bash
# 開発サーバー起動
npm run dev

# ビルド確認
npm run build

# 本番モード起動（テスト用）
npm run start
```

## 🛠️ 開発ツール設定

### VS Code 設定

**.vscode/settings.json:**
```json
{
  "typescript.preferences.importModuleSpecifier": "relative",
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  },
  "files.exclude": {
    "node_modules": true,
    ".next": true
  },
  "emmet.includeLanguages": {
    "typescript": "html",
    "typescriptreact": "html"
  }
}
```

**.vscode/extensions.json:**
```json
{
  "recommendations": [
    "bradlc.vscode-tailwindcss",
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
    "ms-vscode.vscode-typescript-next",
    "formulahendry.auto-rename-tag",
    "christian-kohler.path-intellisense"
  ]
}
```

### Git Hooks セットアップ

```bash
# pre-commit フック作成
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
npm run lint
npm run type-check
EOF

chmod +x .git/hooks/pre-commit
```

## 📊 開発用コマンド

### 基本コマンド

```bash
# 開発サーバー起動
npm run dev

# ビルド
npm run build

# 本番サーバー起動
npm run start

# リンティング
npm run lint

# 型チェック
npm run type-check

# テスト実行
npm test

# テストカバレッジ
npm run test:coverage
```

### データベース操作

```bash
# マイグレーション実行
./infrastructure/scripts/migrate.sh staging

# マイグレーション状態確認
./infrastructure/scripts/migrate.sh staging status

# サンプルデータリセット
./docs/development/scripts/reset-sample-data.sh
```

### 開発用ユーティリティ

```bash
# APIテスト実行
./docs/development/scripts/test-api.sh

# パフォーマンステスト
./docs/development/scripts/performance-test.sh

# セキュリティスキャン
npm audit

# 依存関係アップデート確認
npx npm-check-updates
```

## 🐳 Docker 開発環境

完全にコンテナ化された開発環境を使用したい場合：

### docker-compose.yml

```yaml
version: '3.8'
services:
  app:
    build:
      context: .
      dockerfile: infrastructure/docker/Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      - NODE_ENV=development
      - DB_HOST=mysql
      - DB_USER=root
      - DB_PASSWORD=password
      - DB_NAME=project_forest_dev
    depends_on:
      - mysql

  mysql:
    image: mysql:8.0
    ports:
      - "3306:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=password
      - MYSQL_DATABASE=project_forest_dev
    volumes:
      - mysql_data:/var/lib/mysql
      - ./database/schema.sql:/docker-entrypoint-initdb.d/schema.sql

volumes:
  mysql_data:
```

### Docker 起動

```bash
# Docker 環境起動
docker-compose up -d

# ログ確認
docker-compose logs -f app

# コンテナ内でコマンド実行
docker-compose exec app npm run lint

# 環境停止
docker-compose down
```

## 🧪 テスト環境

### テスト実行

```bash
# 全テスト実行
npm test

# 特定のテストファイル実行
npm test -- __tests__/api/text-entries.test.ts

# ウォッチモード
npm test -- --watch

# カバレッジレポート生成
npm run test:coverage
```

### E2E テスト

```bash
# Playwright インストール（初回のみ）
npx playwright install

# E2E テスト実行
npm run test:e2e

# ヘッドレスモードで実行
npm run test:e2e:headless
```

## 🔧 トラブルシューティング

### よくある問題と解決方法

**1. ポート 3000 が使用中**
```bash
# ポート使用状況確認
lsof -i :3000

# プロセス終了
kill -9 <PID>

# または別ポート使用
PORT=3001 npm run dev
```

**2. データベース接続エラー**
```bash
# MySQL サービス状態確認
systemctl status mysql  # Linux
brew services list      # macOS

# 接続テスト
mysql -u root -p -e "SELECT 1;"

# 権限確認
mysql -u root -p -e "SHOW GRANTS FOR 'root'@'localhost';"
```

**3. Node.js バージョンエラー**
```bash
# Node.js バージョン確認
node --version

# nvm でバージョン切り替え
nvm install 18
nvm use 18
```

**4. npm インストールエラー**
```bash
# キャッシュクリア
npm cache clean --force

# node_modules 削除後再インストール
rm -rf node_modules package-lock.json
npm install
```

**5. TypeScript エラー**
```bash
# 型チェック実行
npm run type-check

# TypeScript サーバー再起動（VS Code）
Ctrl+Shift+P → "TypeScript: Restart TS Server"
```

## 📚 デバッグ方法

### VS Code デバッグ設定

**.vscode/launch.json:**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Next.js: debug server-side",
      "type": "node",
      "request": "attach",
      "port": 9229,
      "skipFiles": ["<node_internals>/**"]
    },
    {
      "name": "Next.js: debug client-side",
      "type": "node",
      "request": "launch",
      "program": "${workspaceFolder}/node_modules/.bin/next",
      "args": ["dev"],
      "skipFiles": ["<node_internals>/**"]
    }
  ]
}
```

### ログレベル設定

```bash
# デバッグログ有効化
DEBUG=* npm run dev

# 特定のモジュールのみ
DEBUG=project-forest:* npm run dev

# ログレベル変更
LOG_LEVEL=debug npm run dev
```

## 🔄 開発ワークフロー

### 推奨開発フロー

1. **機能開発開始**
   ```bash
   git checkout -b feature/new-feature
   npm run dev
   ```

2. **コード変更とテスト**
   ```bash
   # 変更実装
   npm run lint
   npm run type-check
   npm test
   ```

3. **コミットとプッシュ**
   ```bash
   git add .
   git commit -m "feat: add new feature"
   git push origin feature/new-feature
   ```

4. **プルリクエスト作成**
   - GitHub でプルリクエスト作成
   - CI/CD パイプライン実行確認
   - コードレビュー依頼

## 📞 サポート

### ヘルプが必要な場合

1. **ドキュメント確認**
   - [README.md](../../README.md)
   - [API ドキュメント](../api/README.md)

2. **Issue 報告**
   - [GitHub Issues](https://github.com/your-org/project-forest/issues)

3. **チーム連絡**
   - Slack: #project-forest-dev
   - メール: dev-team@example.com

### 便利なリンク

- **ローカル環境**
  - アプリケーション: http://localhost:3000
  - API ドキュメント: http://localhost:3000/api/docs
  - ヘルスチェック: http://localhost:3000/api/health

- **開発ツール**
  - ESLint 設定: [.eslintrc.js](../../.eslintrc.js)
  - Prettier 設定: [.prettierrc](../../.prettierrc)
  - TypeScript 設定: [tsconfig.json](../../tsconfig.json)

---

**Happy Coding! 🚀**