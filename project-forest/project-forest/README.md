# Project Forest - テキスト管理システム

多言語対応ゲーム開発のためのテキスト管理・翻訳システム

## 🚀 クイックスタート

### 必要な環境

- Node.js 18以上
- MySQL 8.0以上
- Git

### ローカル開発環境のセットアップ

```bash
# リポジトリをクローン
git clone https://github.com/your-org/project-forest.git
cd project-forest

# 開発環境のセットアップ（自動）
./infrastructure/scripts/setup-local.sh

# または手動セットアップ
npm install
cp .env.example .env.local
# .env.localファイルを編集してデータベース設定を入力
npm run dev
```

アプリケーションは http://localhost:3000 で利用できます。

## 📋 主な機能

- **テキスト管理**: 多言語テキストの一元管理
- **翻訳ワークフロー**: 翻訳者・レビュアーによる協力的な翻訳プロセス
- **進捗管理**: プロジェクトの翻訳進捗を可視化
- **CSV入出力**: 既存ツールとの連携
- **履歴管理**: 全ての変更を追跡・復元可能
- **ユーザー管理**: ロールベースのアクセス制御

## 🏗️ アーキテクチャ

- **フロントエンド**: Next.js 15, React 19, TypeScript, Tailwind CSS
- **バックエンド**: Next.js API Routes, Node.js
- **データベース**: MySQL 8.0
- **認証**: JWT
- **デプロイ**: Docker, Kubernetes
- **CI/CD**: GitHub Actions

## 📚 開発ガイド

### プロジェクト構造

```
project-forest/
├── app/                    # Next.js アプリケーション
│   ├── api/               # API ルート
│   ├── components/        # React コンポーネント
│   └── globals.css        # グローバルスタイル
├── database/              # データベース関連
│   ├── schema.sql         # データベーススキーマ
│   └── migrations/        # マイグレーションファイル
├── infrastructure/        # インフラ設定
│   ├── configs/          # Kubernetes設定
│   ├── docker/           # Docker設定
│   └── scripts/          # デプロイスクリプト
├── lib/                   # 共通ライブラリ
│   ├── database.ts       # データベース接続
│   └── types.ts          # TypeScript型定義
└── .github/              # GitHub Actions
    └── workflows/        # CI/CDワークフロー
```

### 利用可能なスクリプト

```bash
# 開発
npm run dev              # 開発サーバー起動
npm run build            # プロダクションビルド
npm run start            # プロダクションサーバー起動
npm run lint             # コードリンティング
npm test                 # テスト実行

# インフラ
./infrastructure/scripts/build.sh          # アプリケーションビルド
./infrastructure/scripts/deploy.sh         # デプロイ
./infrastructure/scripts/migrate.sh        # データベースマイグレーション
./infrastructure/scripts/smoke-test.sh     # スモークテスト
./infrastructure/scripts/setup-local.sh    # ローカル環境セットアップ
```

### データベースマイグレーション

```bash
# 本番環境へのマイグレーション
./infrastructure/scripts/migrate.sh production

# ステージング環境へのマイグレーション
./infrastructure/scripts/migrate.sh staging

# マイグレーション状況確認
./infrastructure/scripts/migrate.sh staging status

# ロールバック（ステージングのみ）
./infrastructure/scripts/migrate.sh staging rollback
```

## 🚢 デプロイ

### GitHub Actions による自動デプロイ

1. **ステージング**: `develop` ブランチへのプッシュ時に自動デプロイ
2. **本番**: `main` ブランチへのプッシュ時に自動デプロイ

### 手動デプロイ

```bash
# ステージング環境
./infrastructure/scripts/deploy.sh staging latest

# 本番環境
./infrastructure/scripts/deploy.sh production v1.2.3
```

### Docker を使用したデプロイ

```bash
# イメージビルド
./infrastructure/scripts/build.sh --docker --tag v1.2.3

# イメージをプッシュ
./infrastructure/scripts/build.sh --docker --push --tag v1.2.3
```

## 🔒 セキュリティ

- **認証**: JWT ベースの認証システム
- **認可**: ロールベースアクセス制御（RBAC）
- **暗号化**: パスワードの bcrypt ハッシュ化
- **セキュリティヘッダー**: 適切なHTTPセキュリティヘッダーの設定
- **入力検証**: 全ての入力データの検証
- **SQLインジェクション対策**: パラメータ化クエリの使用

## 📊 監視・ログ

- **ヘルスチェック**: `/api/health` エンドポイント
- **メトリクス**: Prometheus メトリクス（`:9090/metrics`）
- **ログ**: 構造化ログ（JSON形式）
- **トレーシング**: 分散トレーシング対応

## 🧪 テスト

```bash
# 全テスト実行
npm test

# 特定のテストファイル実行
npm test -- __tests__/api/text-entries.test.ts

# カバレッジレポート生成
npm run test:coverage
```

### スモークテスト

```bash
# ローカル環境
./infrastructure/scripts/smoke-test.sh http://localhost:3000

# ステージング環境
./infrastructure/scripts/smoke-test.sh https://staging.project-forest.example.com
```

## 🔧 設定

### 環境変数

| 変数名 | 説明 | デフォルト値 |
|--------|------|-------------|
| `NODE_ENV` | 実行環境 | `development` |
| `DB_HOST` | データベースホスト | `localhost` |
| `DB_USER` | データベースユーザー | `root` |
| `DB_PASSWORD` | データベースパスワード | - |
| `DB_NAME` | データベース名 | `project_forest_dev` |
| `JWT_SECRET` | JWT 署名キー | - |
| `API_RATE_LIMIT` | API レート制限 | `1000` |

### 機能フラグ

| フラグ名 | 説明 | デフォルト値 |
|---------|------|-------------|
| `ENABLE_TRANSLATION_API` | 翻訳API連携 | `true` |
| `ENABLE_CSV_IMPORT` | CSV インポート | `true` |
| `ENABLE_WEBSOCKETS` | WebSocket 機能 | `true` |
| `ENABLE_AUDIT_LOG` | 監査ログ | `true` |

## 🤝 コントリビューション

1. フォークする
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

### コーディング規約

- **ESLint**: コードの品質とスタイルを維持
- **Prettier**: コードフォーマッタ
- **TypeScript**: 型安全性を確保
- **コミットメッセージ**: Conventional Commits形式

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。詳細は [LICENSE](LICENSE) ファイルを参照してください。

## 🆘 サポート

- **バグレポート**: [GitHub Issues](https://github.com/your-org/project-forest/issues)
- **機能要求**: [GitHub Discussions](https://github.com/your-org/project-forest/discussions)
- **ドキュメント**: [Wiki](https://github.com/your-org/project-forest/wiki)

## 📈 ロードマップ

- [ ] AI翻訳支援機能
- [ ] リアルタイム編集機能
- [ ] Unreal Engine連携
- [ ] モバイル対応
- [ ] 多言語UI対応
- [ ] ワークフロー自動化

---

**Project Forest** - Making multilingual game development easier and more efficient.
