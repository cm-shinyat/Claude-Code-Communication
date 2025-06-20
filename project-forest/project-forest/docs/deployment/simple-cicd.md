# 簡素化 CI/CD 設定ガイド

開発者向けのシンプルで理解しやすい CI/CD パイプライン設定ガイドです。

## 🎯 概要

複雑なKubernetesやオーケストレーションを避けて、ECS Fargate を使用したシンプルなCI/CDパイプラインを構築します。

## 📋 アーキテクチャ

```
GitHub → GitHub Actions → ECR → ECS Fargate
                ↓
        RDS MySQL + Secrets Manager
```

## 🚀 GitHub Actions ワークフロー（簡素版）

### .github/workflows/simple-deploy.yml

```yaml
name: Simple Deploy

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  AWS_REGION: ap-northeast-1
  ECR_REPOSITORY: project-forest

jobs:
  # テストとビルド
  test-and-build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run linting
        run: npm run lint

      - name: Run tests
        run: npm test

      - name: Build application
        run: npm run build

      - name: Build Docker image
        run: |
          docker build -f infrastructure/docker/Dockerfile -t $ECR_REPOSITORY:$GITHUB_SHA .

      - name: Save Docker image
        run: |
          docker save $ECR_REPOSITORY:$GITHUB_SHA | gzip > image.tar.gz

      - name: Upload image artifact
        uses: actions/upload-artifact@v4
        with:
          name: docker-image
          path: image.tar.gz

  # ステージングデプロイ
  deploy-staging:
    needs: test-and-build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'
    environment: staging
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Download image artifact
        uses: actions/download-artifact@v4
        with:
          name: docker-image

      - name: Load Docker image
        run: |
          docker load < image.tar.gz

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Tag and push image
        run: |
          docker tag $ECR_REPOSITORY:$GITHUB_SHA ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:staging
          docker tag $ECR_REPOSITORY:$GITHUB_SHA ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:$GITHUB_SHA
          docker push ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:staging
          docker push ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:$GITHUB_SHA

      - name: Deploy to ECS
        run: |
          # タスク定義更新
          aws ecs register-task-definition \
            --cli-input-json file://docs/deployment/task-definitions/staging.json \
            --region $AWS_REGION

          # サービス更新
          aws ecs update-service \
            --cluster project-forest-staging \
            --service project-forest-service \
            --task-definition project-forest-staging \
            --region $AWS_REGION

          # デプロイ完了まで待機
          aws ecs wait services-stable \
            --cluster project-forest-staging \
            --services project-forest-service \
            --region $AWS_REGION

      - name: Run smoke tests
        run: |
          sleep 30  # サービス起動待機
          curl -f https://staging.project-forest.example.com/api/health

  # 本番デプロイ
  deploy-production:
    needs: test-and-build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Download image artifact
        uses: actions/download-artifact@v4
        with:
          name: docker-image

      - name: Load Docker image
        run: |
          docker load < image.tar.gz

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Tag and push image
        run: |
          docker tag $ECR_REPOSITORY:$GITHUB_SHA ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:latest
          docker tag $ECR_REPOSITORY:$GITHUB_SHA ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:$GITHUB_SHA
          docker push ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:latest
          docker push ${{ secrets.ECR_REGISTRY }}/$ECR_REPOSITORY:$GITHUB_SHA

      - name: Run database migrations
        run: |
          # マイグレーション実行スクリプト
          ./docs/deployment/scripts/run-migration.sh production

      - name: Deploy to ECS
        run: |
          # タスク定義更新
          aws ecs register-task-definition \
            --cli-input-json file://docs/deployment/task-definitions/production.json \
            --region $AWS_REGION

          # サービス更新
          aws ecs update-service \
            --cluster project-forest-production \
            --service project-forest-service \
            --task-definition project-forest-production \
            --region $AWS_REGION

          # デプロイ完了まで待機
          aws ecs wait services-stable \
            --cluster project-forest-production \
            --services project-forest-service \
            --region $AWS_REGION

      - name: Run smoke tests
        run: |
          sleep 30  # サービス起動待機
          curl -f https://project-forest.example.com/api/health

      - name: Notify success
        if: success()
        run: |
          echo "✅ Production deployment successful!"
          # Slack通知などをここに追加

      - name: Notify failure
        if: failure()
        run: |
          echo "❌ Production deployment failed!"
          # Slack通知などをここに追加
```

## 📄 GitHub シークレット設定

### 必要なシークレット

**Repository secrets:**
```
AWS_ACCESS_KEY_ID          # AWS アクセスキー
AWS_SECRET_ACCESS_KEY      # AWS シークレットキー
ECR_REGISTRY              # ECR レジストリURL (123456789012.dkr.ecr.ap-northeast-1.amazonaws.com)
```

**Environment secrets (staging):**
```
DB_HOST                   # ステージング DB ホスト
DB_NAME                   # ステージング DB 名
DB_USER                   # ステージング DB ユーザー
DB_PASSWORD               # ステージング DB パスワード
JWT_SECRET                # ステージング JWT シークレット
```

**Environment secrets (production):**
```
DB_HOST                   # 本番 DB ホスト
DB_NAME                   # 本番 DB 名
DB_USER                   # 本番 DB ユーザー
DB_PASSWORD               # 本番 DB パスワード
JWT_SECRET                # 本番 JWT シークレット
```

## 🔧 ECS タスク定義（簡素版）

### staging 環境

**docs/deployment/task-definitions/staging.json:**
```json
{
  "family": "project-forest-staging",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "project-forest-app",
      "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:staging",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "staging"
        },
        {
          "name": "APP_PORT",
          "value": "3000"
        },
        {
          "name": "DB_HOST",
          "value": "project-forest-staging.123456789012.ap-northeast-1.rds.amazonaws.com"
        },
        {
          "name": "DB_PORT",
          "value": "3306"
        },
        {
          "name": "DB_NAME",
          "value": "project_forest_staging"
        },
        {
          "name": "DB_USER",
          "value": "admin"
        }
      ],
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/staging/db-password-AbCdEf"
        },
        {
          "name": "JWT_SECRET",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/staging/jwt-secret-AbCdEf"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/project-forest-staging",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:3000/api/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

### production 環境

**docs/deployment/task-definitions/production.json:**
```json
{
  "family": "project-forest-production",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "project-forest-app",
      "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "APP_PORT",
          "value": "3000"
        },
        {
          "name": "DB_HOST",
          "value": "project-forest-production.123456789012.ap-northeast-1.rds.amazonaws.com"
        },
        {
          "name": "DB_PORT",
          "value": "3306"
        },
        {
          "name": "DB_NAME",
          "value": "project_forest_production"
        },
        {
          "name": "DB_USER",
          "value": "admin"
        }
      ],
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/production/db-password-AbCdEf"
        },
        {
          "name": "JWT_SECRET",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/production/jwt-secret-AbCdEf"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/project-forest-production",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:3000/api/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

## 🔄 デプロイフロー

### 開発フロー

1. **機能開発**
   ```bash
   git checkout -b feature/new-feature
   # 開発作業
   git commit -m "feat: add new feature"
   git push origin feature/new-feature
   ```

2. **プルリクエスト**
   - GitHub でプルリクエスト作成
   - CI パイプライン（テスト・ビルド）が自動実行
   - コードレビュー

3. **ステージングデプロイ**
   ```bash
   git checkout develop
   git merge feature/new-feature
   git push origin develop
   # → 自動的にステージング環境にデプロイ
   ```

4. **本番デプロイ**
   ```bash
   git checkout main
   git merge develop
   git push origin main
   # → 自動的に本番環境にデプロイ
   ```

### 手動デプロイ

緊急時やテスト目的での手動デプロイ：

```bash
# ステージング環境へ手動デプロイ
./docs/deployment/scripts/manual-deploy.sh staging

# 本番環境へ手動デプロイ
./docs/deployment/scripts/manual-deploy.sh production
```

## 📊 監視とアラート

### CloudWatch アラーム

**基本アラーム設定スクリプト:**
```bash
#!/bin/bash
# docs/deployment/scripts/setup-alarms.sh

ENVIRONMENT=${1:-staging}

# CPU使用率アラーム
aws cloudwatch put-metric-alarm \
  --alarm-name "project-forest-${ENVIRONMENT}-high-cpu" \
  --alarm-description "High CPU usage" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=project-forest-service Name=ClusterName,Value=project-forest-${ENVIRONMENT}

# メモリ使用率アラーム
aws cloudwatch put-metric-alarm \
  --alarm-name "project-forest-${ENVIRONMENT}-high-memory" \
  --alarm-description "High memory usage" \
  --metric-name MemoryUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=project-forest-service Name=ClusterName,Value=project-forest-${ENVIRONMENT}

# アプリケーションエラーアラーム
aws logs put-metric-filter \
  --log-group-name "/ecs/project-forest-${ENVIRONMENT}" \
  --filter-name "ErrorFilter" \
  --filter-pattern "ERROR" \
  --metric-transformations \
    metricName=ApplicationErrors,metricNamespace=ProjectForest,metricValue=1

aws cloudwatch put-metric-alarm \
  --alarm-name "project-forest-${ENVIRONMENT}-errors" \
  --alarm-description "Application errors detected" \
  --metric-name ApplicationErrors \
  --namespace ProjectForest \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1
```

### ログ監視

```bash
# リアルタイムログ確認
aws logs tail /ecs/project-forest-staging --follow

# エラーログのみ抽出
aws logs filter-log-events \
  --log-group-name /ecs/project-forest-staging \
  --filter-pattern "ERROR"

# 特定期間のログ抽出
aws logs filter-log-events \
  --log-group-name /ecs/project-forest-staging \
  --start-time $(date -d '1 hour ago' +%s)000
```

## 🔧 トラブルシューティング

### デプロイ失敗時の対処

1. **GitHub Actions ログ確認**
   - Actions タブでワークフロー実行ログを確認
   - 失敗したステップの詳細を確認

2. **ECS サービス状態確認**
   ```bash
   aws ecs describe-services \
     --cluster project-forest-staging \
     --services project-forest-service
   ```

3. **タスク状態確認**
   ```bash
   aws ecs list-tasks \
     --cluster project-forest-staging \
     --service-name project-forest-service
   
   aws ecs describe-tasks \
     --cluster project-forest-staging \
     --tasks <task-arn>
   ```

4. **ロールバック**
   ```bash
   # 前のタスク定義にロールバック
   aws ecs update-service \
     --cluster project-forest-staging \
     --service project-forest-service \
     --task-definition project-forest-staging:PREVIOUS_REVISION
   ```

### よくある問題

**1. イメージプルエラー**
- ECR 権限の確認
- イメージタグの確認
- ネットワーク設定の確認

**2. ヘルスチェック失敗**
- アプリケーションログの確認
- ヘルスチェックエンドポイントの動作確認
- セキュリティグループの設定確認

**3. データベース接続エラー**
- RDS 接続設定の確認
- Secrets Manager の権限確認
- セキュリティグループの設定確認

## 💡 最適化のヒント

### パフォーマンス最適化

1. **タスクサイズの調整**
   - CPU/メモリ使用率を監視して適切なサイズを設定
   - staging: 512 CPU / 1024 Memory
   - production: 1024 CPU / 2048 Memory

2. **Auto Scaling 設定**
   ```bash
   # Auto Scaling ターゲット登録
   aws application-autoscaling register-scalable-target \
     --service-namespace ecs \
     --scalable-dimension ecs:service:DesiredCount \
     --resource-id service/project-forest-production/project-forest-service \
     --min-capacity 2 \
     --max-capacity 10
   ```

3. **キャッシュ戦略**
   - Redis を ElastiCache で追加
   - CloudFront での静的ファイルキャッシュ

### コスト最適化

1. **Fargate Spot の活用**
   - ステージング環境で Spot インスタンス使用
   - 最大50%のコスト削減

2. **不要リソースの自動削除**
   - 古いタスク定義の定期削除
   - 未使用のECRイメージの削除

3. **環境の自動停止**
   - ステージング環境の夜間停止スケジュール設定

---

このシンプルなCI/CD設定により、複雑なオーケストレーションなしでも安定したデプロイメントパイプラインを構築できます。