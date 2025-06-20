# ECS Fargate デプロイメントガイド

Project Forest を AWS ECS Fargate にデプロイするための簡易手順書です。

## 🎯 概要

このガイドでは、開発・ステージング・本番環境向けに ECS Fargate を使用したシンプルなデプロイメント方法を説明します。

## 📋 前提条件

- AWS CLI v2 がインストールされていること
- Docker がインストールされていること
- AWS アカウントと適切な権限があること
- ECR リポジトリが作成されていること

## 🚀 クイックスタート

### 1. 環境変数の設定

```bash
# AWS 設定
export AWS_REGION=ap-northeast-1
export AWS_ACCOUNT_ID=123456789012
export ECR_REGISTRY=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
export ECR_REPOSITORY=project-forest

# アプリケーション設定
export ENVIRONMENT=staging  # staging | production
export APP_VERSION=latest
```

### 2. ECR リポジトリの準備

```bash
# ECR リポジトリ作成（初回のみ）
aws ecr create-repository \
    --repository-name project-forest \
    --region ${AWS_REGION}

# Docker ログイン
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}
```

### 3. Docker イメージのビルドとプッシュ

```bash
# イメージビルド
docker build -f infrastructure/docker/Dockerfile \
    -t ${ECR_REGISTRY}/${ECR_REPOSITORY}:${APP_VERSION} .

# イメージプッシュ
docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${APP_VERSION}
```

### 4. ECS クラスターとサービスの作成

```bash
# クラスター作成（初回のみ）
aws ecs create-cluster \
    --cluster-name project-forest-${ENVIRONMENT} \
    --region ${AWS_REGION}

# タスク定義とサービスのデプロイ
./docs/deployment/scripts/deploy-ecs.sh ${ENVIRONMENT} ${APP_VERSION}
```

## 📄 ECS タスク定義

### staging 環境用タスク定義

```json
{
  "family": "project-forest-staging",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/project-forest-task-role",
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
          "value": "staging"
        },
        {
          "name": "APP_PORT",
          "value": "3000"
        }
      ],
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/staging/db-password"
        },
        {
          "name": "JWT_SECRET",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/staging/jwt-secret"
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

### production 環境用タスク定義

```json
{
  "family": "project-forest-production",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/project-forest-task-role",
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
        }
      ],
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/production/db-password"
        },
        {
          "name": "JWT_SECRET",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/production/jwt-secret"
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

## 🔧 必要な AWS リソース

### 1. IAM ロール

**ECS タスク実行ロール**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "*"
    }
  ]
}
```

**ECS タスクロール**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:project-forest/*",
        "arn:aws:s3:::project-forest-uploads/*"
      ]
    }
  ]
}
```

### 2. Secrets Manager

```bash
# データベースパスワード
aws secretsmanager create-secret \
    --name "project-forest/staging/db-password" \
    --description "Database password for staging environment" \
    --secret-string "your-secure-password"

# JWT シークレット
aws secretsmanager create-secret \
    --name "project-forest/staging/jwt-secret" \
    --description "JWT secret for staging environment" \
    --secret-string "your-jwt-secret-key"
```

### 3. RDS データベース

```bash
# サブネットグループ作成
aws rds create-db-subnet-group \
    --db-subnet-group-name project-forest-subnet-group \
    --db-subnet-group-description "Subnet group for Project Forest" \
    --subnet-ids subnet-12345678 subnet-87654321

# セキュリティグループ作成
aws ec2 create-security-group \
    --group-name project-forest-db-sg \
    --description "Security group for Project Forest database"

# MySQL インスタンス作成
aws rds create-db-instance \
    --db-instance-identifier project-forest-staging \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --engine-version 8.0.35 \
    --master-username admin \
    --master-user-password your-secure-password \
    --allocated-storage 20 \
    --vpc-security-group-ids sg-12345678 \
    --db-subnet-group-name project-forest-subnet-group \
    --backup-retention-period 7 \
    --storage-encrypted
```

### 4. Application Load Balancer

```bash
# ALB 作成
aws elbv2 create-load-balancer \
    --name project-forest-alb \
    --subnets subnet-12345678 subnet-87654321 \
    --security-groups sg-12345678

# ターゲットグループ作成
aws elbv2 create-target-group \
    --name project-forest-tg \
    --protocol HTTP \
    --port 3000 \
    --vpc-id vpc-12345678 \
    --target-type ip \
    --health-check-path /api/health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3

# リスナー作成
aws elbv2 create-listener \
    --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/project-forest-alb/1234567890123456 \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/project-forest-tg/1234567890123456
```

## 🔄 デプロイメント手順

### 自動デプロイ

```bash
# 完全自動デプロイ
./docs/deployment/scripts/full-deploy.sh staging

# または本番環境
./docs/deployment/scripts/full-deploy.sh production v1.2.3
```

### 手動デプロイ

```bash
# 1. イメージビルドとプッシュ
./docs/deployment/scripts/build-and-push.sh latest

# 2. タスク定義更新
./docs/deployment/scripts/update-task-definition.sh staging latest

# 3. サービス更新
aws ecs update-service \
    --cluster project-forest-staging \
    --service project-forest-service \
    --task-definition project-forest-staging:LATEST

# 4. デプロイ状況確認
aws ecs wait services-stable \
    --cluster project-forest-staging \
    --services project-forest-service
```

## 📊 監視とログ

### CloudWatch ログ

```bash
# ログ確認
aws logs tail /ecs/project-forest-staging --follow

# エラーログのみ表示
aws logs filter-log-events \
    --log-group-name /ecs/project-forest-staging \
    --filter-pattern "ERROR"
```

### CloudWatch メトリクス

- CPU 使用率
- メモリ使用率
- タスク数
- ALB ターゲットの健全性

### アラーム設定

```bash
# CPU 使用率アラーム
aws cloudwatch put-metric-alarm \
    --alarm-name "project-forest-high-cpu" \
    --alarm-description "High CPU usage" \
    --metric-name CPUUtilization \
    --namespace AWS/ECS \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2
```

## 🔧 トラブルシューティング

### よくある問題

**1. タスクが起動しない**
```bash
# サービスイベント確認
aws ecs describe-services \
    --cluster project-forest-staging \
    --services project-forest-service

# タスク詳細確認
aws ecs describe-tasks \
    --cluster project-forest-staging \
    --tasks task-id
```

**2. ヘルスチェック失敗**
```bash
# ログ確認
aws logs tail /ecs/project-forest-staging --follow

# コンテナ内でヘルスチェック実行
aws ecs execute-command \
    --cluster project-forest-staging \
    --task task-id \
    --container project-forest-app \
    --interactive \
    --command "/bin/sh"
```

**3. データベース接続エラー**
- セキュリティグループの設定確認
- RDS エンドポイントの確認
- Secrets Manager の権限確認

## 📚 参考資料

- [AWS ECS Fargate 公式ドキュメント](https://docs.aws.amazon.com/ecs/latest/userguide/AWS_Fargate.html)
- [ECS CLI リファレンス](https://docs.aws.amazon.com/cli/latest/reference/ecs/)
- [CloudWatch ログ設定](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_awslogs.html)

## 💡 ベストプラクティス

1. **セキュリティ**
   - Secrets Manager を使用して機密情報を管理
   - タスクロールで最小権限の原則を適用
   - VPC 内でプライベートサブネットを使用

2. **可用性**
   - 複数 AZ での冗長化
   - Auto Scaling の設定
   - ヘルスチェックの適切な設定

3. **監視**
   - CloudWatch ログとメトリクスの活用
   - アラームの設定
   - X-Ray トレーシングの有効化

4. **コスト最適化**
   - Fargate Spot の活用
   - 適切なタスクサイズの設定
   - 不要なリソースの定期的な削除