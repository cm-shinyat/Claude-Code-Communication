# Project Forest 開発環境デプロイ手順（aws-vault対応版）

`aws-vault` を使用したセキュアなAWS環境へのデプロイ手順です。

## 目次

1. [開発環境の選択](#開発環境の選択)
2. [ローカル開発環境](#1-ローカル開発環境aws不要)
3. [AWS環境へのデプロイ](#2-aws環境へのデプロイaws-vault使用)
4. [デプロイスクリプトの修正](#3-デプロイスクリプトの-aws-vault-対応修正)
5. [便利なエイリアス設定](#4-便利なエイリアス設定)
6. [ワンライナーデプロイ](#5-ワンライナーデプロイコマンド)
7. [トラブルシューティング](#6-トラブルシューティング)
8. [セキュリティベストプラクティス](#セキュリティベストプラクティス)

## 開発環境の選択

Project Forest の開発環境は以下の2つから選択できます：

- **ローカル開発環境**: AWS不要で、ローカルマシンで完結
- **AWS環境**: aws-vault を使用したセキュアなクラウド環境

## 1. ローカル開発環境（AWS不要）

ローカルマシンで開発を行う場合の手順です。

```bash
# リポジトリクローン
git clone https://github.com/your-org/project-forest.git
cd project-forest/project-forest

# 自動セットアップ実行
./infrastructure/scripts/setup-local.sh

# オプション付き実行例
./infrastructure/scripts/setup-local.sh --reset-db  # データベースリセット付き
./infrastructure/scripts/setup-local.sh --skip-deps # 依存関係インストールをスキップ
```

### セットアップ内容

- Node.js依存関係のインストール
- 環境設定ファイル（.env.local）の作成
- MySQLデータベースのセットアップ
- サンプルデータの投入
- 開発サーバーの起動（http://localhost:3000）

### デフォルトログイン情報

| メールアドレス | パスワード | ロール |
|--------------|----------|--------|
| admin@example.com | password | 管理者 |
| writer@example.com | password | シナリオライター |
| translator@example.com | password | 翻訳者 |
| reviewer@example.com | password | レビュアー |

## 2. AWS環境へのデプロイ（aws-vault使用）

### 前提条件

- aws-vault のインストール
- AWS アカウントへのアクセス権限
- Docker のインストール

### 初期設定

```bash
# aws-vault にプロファイル追加（初回のみ）
aws-vault add shinyat

# 認証確認
aws-vault exec shinyat -- aws sts get-caller-identity
```

### ECRへのDockerイメージプッシュ

```bash
# アカウントIDを取得
ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)

# ECRログイン
aws-vault exec shinyat -- aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com

# Dockerイメージビルド
docker build -f infrastructure/docker/Dockerfile -t project-forest:latest .

# タグ付けとプッシュ
docker tag project-forest:latest ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest
docker push ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest
```

### ECSへのデプロイ

```bash
# タスク定義の登録
aws-vault exec shinyat -- aws ecs register-task-definition \
  --cli-input-json file://docs/deployment/task-definitions/staging.json

# サービスの更新
aws-vault exec shinyat -- aws ecs update-service \
  --cluster project-forest-staging \
  --service project-forest-service \
  --task-definition project-forest-staging

# デプロイ完了待機
aws-vault exec shinyat -- aws ecs wait services-stable \
  --cluster project-forest-staging \
  --services project-forest-service
```

## 3. デプロイスクリプトの aws-vault 対応修正

既存のデプロイスクリプトを aws-vault で使用するためのラッパースクリプト：

```bash
# deploy-with-vault.sh の作成
cat > deploy-with-vault.sh << 'EOF'
#!/bin/bash
set -euo pipefail

ENVIRONMENT=${1:-staging}
IMAGE_TAG=${2:-latest}
AWS_PROFILE=${AWS_PROFILE:-shinyat}

echo "🚀 Deploying to $ENVIRONMENT with aws-vault profile: $AWS_PROFILE"

# aws-vault を使ってデプロイスクリプト実行
aws-vault exec $AWS_PROFILE -- ./infrastructure/scripts/deploy.sh $ENVIRONMENT $IMAGE_TAG
EOF

chmod +x deploy-with-vault.sh

# 使用例
./deploy-with-vault.sh staging latest
./deploy-with-vault.sh production v1.0.0
```

## 4. 便利なエイリアス設定

`.bashrc` または `.zshrc` に追加：

```bash
# aws-vault を使った Project Forest コマンド
alias pf-ecr-login='aws-vault exec shinyat -- aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-northeast-1.amazonaws.com'
alias pf-logs-staging='aws-vault exec shinyat -- aws logs tail /ecs/project-forest-staging --follow'
alias pf-logs-prod='aws-vault exec shinyat -- aws logs tail /ecs/project-forest-production --follow'
alias pf-ecs-status='aws-vault exec shinyat -- aws ecs describe-services --cluster project-forest-staging --services project-forest-service'
alias pf-deploy-staging='aws-vault exec shinyat -- ./infrastructure/scripts/deploy.sh staging'
alias pf-deploy-prod='aws-vault exec shinyat -- ./infrastructure/scripts/deploy.sh production'

# データベース関連
alias pf-db-staging='aws-vault exec shinyat -- aws rds describe-db-instances --db-instance-identifier project-forest-staging'
alias pf-db-prod='aws-vault exec shinyat -- aws rds describe-db-instances --db-instance-identifier project-forest-production'

# S3 関連
alias pf-s3-list='aws-vault exec shinyat -- aws s3 ls s3://project-forest-uploads/'
alias pf-s3-sync='aws-vault exec shinyat -- aws s3 sync ./uploads s3://project-forest-uploads/'
```

## 5. ワンライナーデプロイコマンド

### ステージング環境への簡易デプロイ

```bash
# 完全自動デプロイ（ビルド、プッシュ、デプロイ）
aws-vault exec shinyat -- bash -c '
  set -e
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ECR_URI=${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest
  
  echo "🔐 ECRログイン..."
  aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${ECR_URI%/*}
  
  echo "🏗️  Dockerイメージビルド..."
  docker build -f infrastructure/docker/Dockerfile -t project-forest:latest .
  
  echo "🏷️  タグ付け..."
  docker tag project-forest:latest $ECR_URI:latest
  
  echo "⬆️  ECRへプッシュ..."
  docker push $ECR_URI:latest
  
  echo "🚀 ECSサービス更新..."
  aws ecs update-service --cluster project-forest-staging --service project-forest-service --force-new-deployment
  
  echo "✅ デプロイ完了！"
'
```

### 本番環境への安全なデプロイ

```bash
# バージョンタグ付きデプロイ
VERSION=v1.0.0
aws-vault exec shinyat -- bash -c "
  set -e
  ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text)
  ECR_URI=\${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest
  
  # 確認プロンプト
  read -p '本番環境にデプロイしますか？ (y/N): ' confirm
  if [[ \$confirm != 'y' ]]; then
    echo 'デプロイをキャンセルしました'
    exit 1
  fi
  
  # デプロイ実行
  aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin \${ECR_URI%/*}
  docker build -f infrastructure/docker/Dockerfile -t project-forest:$VERSION .
  docker tag project-forest:$VERSION \$ECR_URI:$VERSION
  docker tag project-forest:$VERSION \$ECR_URI:latest
  docker push \$ECR_URI:$VERSION
  docker push \$ECR_URI:latest
  
  # タスク定義更新
  aws ecs register-task-definition --cli-input-json file://docs/deployment/task-definitions/production.json
  aws ecs update-service --cluster project-forest-production --service project-forest-service --task-definition project-forest-production
"
```

## 6. トラブルシューティング

### ログ確認

```bash
# リアルタイムログ確認
aws-vault exec shinyat -- aws logs tail /ecs/project-forest-staging --follow

# 過去5分間のログ
aws-vault exec shinyat -- aws logs tail /ecs/project-forest-staging --since 5m

# エラーログのみ抽出
aws-vault exec shinyat -- aws logs filter-log-events \
  --log-group-name /ecs/project-forest-staging \
  --filter-pattern "ERROR"
```

### タスクとサービスの状態確認

```bash
# 実行中のタスク一覧
aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster project-forest-staging \
  --service-name project-forest-service

# タスクの詳細情報
TASK_ARN=$(aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster project-forest-staging \
  --service-name project-forest-service \
  --query 'taskArns[0]' --output text)

aws-vault exec shinyat -- aws ecs describe-tasks \
  --cluster project-forest-staging \
  --tasks $TASK_ARN
```

### ネットワーク診断

```bash
# セキュリティグループ確認
aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=project-forest-*"

# ALBターゲットヘルス確認
aws-vault exec shinyat -- aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-1:xxx:targetgroup/project-forest-tg/xxx
```

### データベース接続確認

```bash
# RDS接続情報取得
aws-vault exec shinyat -- aws rds describe-db-instances \
  --db-instance-identifier project-forest-staging \
  --query 'DBInstances[0].Endpoint'

# パラメータグループ確認
aws-vault exec shinyat -- aws rds describe-db-parameter-groups \
  --db-parameter-group-name project-forest-params
```

## セキュリティベストプラクティス

### 1. aws-vault の設定

```bash
# ~/.aws/config の設定例
[profile shinyat]
region = ap-northeast-1
mfa_serial = arn:aws:iam::123456789012:mfa/your-username
aws_vault_backend = keychain  # macOS
aws_session_ttl = 4h
aws_assume_role_ttl = 1h
```

### 2. 環境変数の安全な利用

```bash
# 一時的な環境変数として使用
aws-vault exec shinyat -- env | grep AWS_

# スクリプト内での利用
#!/bin/bash
aws-vault exec shinyat -- bash << 'EOF'
  # AWS認証情報が自動的に環境変数として設定される
  echo "Account: $AWS_ACCOUNT_ID"
  echo "Region: $AWS_REGION"
  # 実際の処理...
EOF
```

### 3. CI/CD での利用

```yaml
# GitHub Actions での例
- name: Deploy to AWS
  run: |
    # GitHub Secrets から認証情報を取得
    aws-vault exec ${{ secrets.AWS_PROFILE }} -- \
      ./infrastructure/scripts/deploy.sh staging
```

### 4. セキュリティチェックリスト

- [ ] aws-vault のバックエンドは OS のキーチェーンを使用
- [ ] MFA を有効化
- [ ] セッションの有効期限を適切に設定
- [ ] 本番環境へのデプロイは承認プロセスを経由
- [ ] ログに認証情報が含まれていないことを確認

## まとめ

このガイドに従うことで、aws-vault を使用した安全な AWS 環境へのデプロイが可能になります。ローカル開発には `setup-local.sh` を、AWS 環境へのデプロイには aws-vault 経由でのコマンド実行を推奨します。

質問や問題がある場合は、プロジェクトチームまでお問い合わせください。