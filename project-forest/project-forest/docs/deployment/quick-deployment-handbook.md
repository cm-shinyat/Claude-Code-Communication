# 簡易デプロイ手順書

Project Forest を最速でデプロイするための実践的な手順書です。

## 🎯 目標

- **15分以内**でステージング環境にデプロイ
- **30分以内**で本番環境にデプロイ
- **開発者フレンドリー**な手順

## 📋 チェックリスト

### デプロイ前チェックリスト

- [ ] AWS CLI インストール済み
- [ ] Docker インストール済み
- [ ] GitHub リポジトリアクセス権限
- [ ] AWS アカウントアクセス権限
- [ ] 環境変数設定完了

## 🚀 クイックスタート（初回セットアップ）

### ステップ 1: リポジトリクローン

```bash
git clone https://github.com/your-org/project-forest.git
cd project-forest
```

### ステップ 2: AWS 認証設定

```bash
# AWS CLI 設定
aws configure
# Access Key ID: YOUR_ACCESS_KEY
# Secret Access Key: YOUR_SECRET_KEY
# Default region: ap-northeast-1
# Default output format: json

# 認証確認
aws sts get-caller-identity
```

### ステップ 3: 初回セットアップ実行

```bash
# 全自動セットアップ（約10分）
./docs/deployment/scripts/first-time-setup.sh

# 手動セットアップの場合
./docs/deployment/scripts/setup-aws-resources.sh
./docs/deployment/scripts/setup-secrets.sh
./docs/deployment/scripts/setup-database.sh
```

### ステップ 4: 初回デプロイ

```bash
# ステージング環境にデプロイ
./docs/deployment/scripts/deploy-to-staging.sh

# 成功確認
curl https://staging.project-forest.example.com/api/health
```

## 📝 日常のデプロイ手順

### シンプルデプロイ（推奨）

```bash
# 1. 最新コードを取得
git pull origin main

# 2. ワンコマンドデプロイ
./docs/deployment/scripts/simple-deploy.sh staging

# 3. 動作確認
./docs/deployment/scripts/health-check.sh staging
```

### GitHub 経由のデプロイ

```bash
# 1. develop ブランチにプッシュ → ステージング自動デプロイ
git checkout develop
git merge feature/my-feature
git push origin develop

# 2. main ブランチにプッシュ → 本番自動デプロイ
git checkout main
git merge develop
git push origin main
```

## 🛠️ デプロイスクリプト詳細

### simple-deploy.sh

**使用法:**
```bash
./docs/deployment/scripts/simple-deploy.sh <environment> [image-tag]
```

**例:**
```bash
# ステージング環境にデプロイ
./docs/deployment/scripts/simple-deploy.sh staging

# 本番環境に特定バージョンをデプロイ
./docs/deployment/scripts/simple-deploy.sh production v1.2.3

# 現在のコミットをデプロイ
./docs/deployment/scripts/simple-deploy.sh staging $(git rev-parse --short HEAD)
```

**スクリプト内容:**
```bash
#!/bin/bash
set -e

ENVIRONMENT=${1:-staging}
IMAGE_TAG=${2:-latest}
AWS_REGION=${AWS_REGION:-ap-northeast-1}
ECR_REPOSITORY=${ECR_REPOSITORY:-project-forest}

echo "🚀 Starting deployment to $ENVIRONMENT"

# 1. Docker イメージビルド
echo "📦 Building Docker image..."
docker build -f infrastructure/docker/Dockerfile -t $ECR_REPOSITORY:$IMAGE_TAG .

# 2. ECR にプッシュ
echo "⬆️ Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com

docker tag $ECR_REPOSITORY:$IMAGE_TAG $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG
docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG

# 3. ECS タスク定義更新
echo "📋 Updating task definition..."
sed "s/{{IMAGE_TAG}}/$IMAGE_TAG/g" docs/deployment/task-definitions/$ENVIRONMENT.json > /tmp/task-definition.json
aws ecs register-task-definition --cli-input-json file:///tmp/task-definition.json

# 4. ECS サービス更新
echo "🔄 Updating ECS service..."
aws ecs update-service \
  --cluster project-forest-$ENVIRONMENT \
  --service project-forest-service \
  --task-definition project-forest-$ENVIRONMENT

# 5. デプロイ完了待機
echo "⏳ Waiting for deployment to complete..."
aws ecs wait services-stable \
  --cluster project-forest-$ENVIRONMENT \
  --services project-forest-service

echo "✅ Deployment completed successfully!"
echo "🌐 Application URL: https://$ENVIRONMENT.project-forest.example.com"
```

### health-check.sh

**使用法:**
```bash
./docs/deployment/scripts/health-check.sh <environment>
```

**スクリプト内容:**
```bash
#!/bin/bash
set -e

ENVIRONMENT=${1:-staging}

if [ "$ENVIRONMENT" = "production" ]; then
  URL="https://project-forest.example.com"
else
  URL="https://$ENVIRONMENT.project-forest.example.com"
fi

echo "🔍 Running health checks for $ENVIRONMENT..."

# ヘルスチェックエンドポイント
echo "📡 Checking health endpoint..."
if curl -sf "$URL/api/health" > /dev/null; then
  echo "✅ Health check passed"
else
  echo "❌ Health check failed"
  exit 1
fi

# データベース接続確認
echo "🗄️ Checking database connection..."
if curl -sf "$URL/api/health/db" > /dev/null; then
  echo "✅ Database connection OK"
else
  echo "❌ Database connection failed"
  exit 1
fi

# API レスポンス確認
echo "🔗 Checking API response..."
if curl -sf "$URL/api/text-entries?limit=1" > /dev/null; then
  echo "✅ API response OK"
else
  echo "❌ API response failed"
  exit 1
fi

echo "🎉 All health checks passed!"
```

### rollback.sh

緊急時のロールバック用スクリプト:

```bash
#!/bin/bash
set -e

ENVIRONMENT=${1:-staging}
REVISION=${2}

echo "🔄 Rolling back $ENVIRONMENT to revision $REVISION"

if [ -z "$REVISION" ]; then
  # 前のリビジョンに自動ロールバック
  REVISION=$(aws ecs list-task-definitions \
    --family-prefix project-forest-$ENVIRONMENT \
    --status ACTIVE \
    --sort DESC \
    --query 'taskDefinitionArns[1]' \
    --output text | cut -d'/' -f2)
fi

echo "📋 Rolling back to task definition: $REVISION"

aws ecs update-service \
  --cluster project-forest-$ENVIRONMENT \
  --service project-forest-service \
  --task-definition $REVISION

echo "⏳ Waiting for rollback to complete..."
aws ecs wait services-stable \
  --cluster project-forest-$ENVIRONMENT \
  --services project-forest-service

echo "✅ Rollback completed!"
```

## 🚨 緊急時対応

### 緊急ロールバック

```bash
# 即座に前のバージョンにロールバック
./docs/deployment/scripts/rollback.sh production

# 特定のリビジョンにロールバック
./docs/deployment/scripts/rollback.sh production project-forest-production:123
```

### サービス再起動

```bash
# サービスを強制的に再起動
aws ecs update-service \
  --cluster project-forest-production \
  --service project-forest-service \
  --force-new-deployment
```

### 緊急スケールアップ

```bash
# タスク数を緊急で増加
aws ecs update-service \
  --cluster project-forest-production \
  --service project-forest-service \
  --desired-count 10
```

## 📊 監視とメンテナンス

### デプロイ状況確認

```bash
# ECS サービス状態確認
./docs/deployment/scripts/check-status.sh production

# 実行中のタスク一覧
aws ecs list-tasks \
  --cluster project-forest-production \
  --service-name project-forest-service

# ログ確認
aws logs tail /ecs/project-forest-production --follow
```

### メトリクス確認

```bash
# CPU/メモリ使用率確認
./docs/deployment/scripts/check-metrics.sh production

# アプリケーションメトリクス
curl https://project-forest.example.com/api/metrics
```

### 定期メンテナンス

```bash
# 古いタスク定義の削除（月次）
./docs/deployment/scripts/cleanup-old-task-definitions.sh

# 未使用ECRイメージの削除（週次）
./docs/deployment/scripts/cleanup-ecr-images.sh

# ログローテーション設定確認
./docs/deployment/scripts/check-log-retention.sh
```

## 🔧 トラブルシューティング

### よくある問題と解決方法

**1. デプロイがタイムアウトする**
```bash
# タスクが起動しない場合
aws ecs describe-tasks --cluster project-forest-staging --tasks $(aws ecs list-tasks --cluster project-forest-staging --service-name project-forest-service --query 'taskArns[0]' --output text)

# ログ確認
aws logs tail /ecs/project-forest-staging --since 5m
```

**2. ヘルスチェックが失敗する**
```bash
# アプリケーションログ確認
aws logs filter-log-events \
  --log-group-name /ecs/project-forest-staging \
  --filter-pattern "ERROR"

# ポート設定確認
aws ecs describe-task-definition \
  --task-definition project-forest-staging \
  --query 'taskDefinition.containerDefinitions[0].portMappings'
```

**3. データベース接続エラー**
```bash
# セキュリティグループ確認
aws ec2 describe-security-groups --group-ids sg-xxx

# RDS 接続確認
mysql -h project-forest-staging.xxx.ap-northeast-1.rds.amazonaws.com -u admin -p
```

**4. イメージプルエラー**
```bash
# ECR 権限確認
aws ecr describe-repository --repository-name project-forest

# イメージ存在確認
aws ecr list-images --repository-name project-forest
```

### デバッグコマンド集

```bash
# ECS サービス詳細情報
aws ecs describe-services \
  --cluster project-forest-production \
  --services project-forest-service

# タスク定義詳細
aws ecs describe-task-definition \
  --task-definition project-forest-production

# CloudWatch ログ確認
aws logs describe-log-groups --log-group-name-prefix "/ecs/project-forest"

# ALB ターゲット健全性確認
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-1:xxx:targetgroup/project-forest-tg/xxx
```

## ⚡ パフォーマンス最適化

### デプロイ高速化

1. **並列ビルド**
   ```bash
   # マルチステージビルドの活用
   docker build --target production -f infrastructure/docker/Dockerfile .
   ```

2. **イメージ層キャッシュ**
   ```bash
   # BuildKit の活用
   DOCKER_BUILDKIT=1 docker build --cache-from project-forest:latest .
   ```

3. **最小限のデプロイ**
   ```bash
   # 変更されたファイルのみをデプロイ
   ./docs/deployment/scripts/incremental-deploy.sh
   ```

### スケーリング戦略

```bash
# Auto Scaling 有効化
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/project-forest-production/project-forest-service \
  --min-capacity 2 \
  --max-capacity 20

# CPU ベースのスケーリングポリシー
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/project-forest-production/project-forest-service \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json
```

## 📚 参考情報

### 便利なエイリアス

**.bashrc や .zshrc に追加:**
```bash
# Project Forest デプロイ関連
alias pf-deploy-staging='./docs/deployment/scripts/simple-deploy.sh staging'
alias pf-deploy-prod='./docs/deployment/scripts/simple-deploy.sh production'
alias pf-health-staging='./docs/deployment/scripts/health-check.sh staging'
alias pf-health-prod='./docs/deployment/scripts/health-check.sh production'
alias pf-logs-staging='aws logs tail /ecs/project-forest-staging --follow'
alias pf-logs-prod='aws logs tail /ecs/project-forest-production --follow'
alias pf-status='aws ecs describe-services --cluster project-forest-production --services project-forest-service'
```

### 設定ファイルテンプレート

**~/.aws/config:**
```ini
[default]
region = ap-northeast-1
output = json

[profile project-forest-staging]
region = ap-northeast-1
role_arn = arn:aws:iam::123456789012:role/ProjectForestStagingRole

[profile project-forest-production]
region = ap-northeast-1
role_arn = arn:aws:iam::123456789012:role/ProjectForestProductionRole
```

### 緊急連絡先

- **開発チーム**: dev-team@example.com
- **運用チーム**: ops-team@example.com
- **オンコール**: +81-90-xxxx-xxxx

---

**🎯 この手順書で、誰でも迅速かつ安全にProject Forestをデプロイできます！**