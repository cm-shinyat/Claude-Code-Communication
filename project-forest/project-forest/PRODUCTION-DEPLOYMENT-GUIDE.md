# Project Forest 本番デプロイガイド

このガイドではProject Forestアプリケーションを本番環境にデプロイする手順を説明します。

## 前提条件

- AWS CLI設定済み（aws-vault使用）
- Docker インストール済み
- MySQL 8.0以降

## デプロイ手順

### 1. 環境設定

#### 環境変数設定
```bash
export AWS_REGION=ap-northeast-1
export PROJECT_NAME=project-forest
export ECR_REPOSITORY_NAME=${PROJECT_NAME}-app
export CLUSTER_NAME=${PROJECT_NAME}-cluster
export SERVICE_NAME=${PROJECT_NAME}-service
export TASK_DEFINITION_NAME=${PROJECT_NAME}-task
```

### 2. ECRリポジトリ作成

```bash
aws-vault exec shinyat -- aws ecr create-repository \
  --repository-name ${ECR_REPOSITORY_NAME} \
  --region ${AWS_REGION}

# ECR URI取得
export ECR_URI=$(aws-vault exec shinyat -- aws ecr describe-repositories \
  --repository-names ${ECR_REPOSITORY_NAME} \
  --region ${AWS_REGION} \
  --query 'repositories[0].repositoryUri' \
  --output text)

echo "ECR URI: ${ECR_URI}"
```

### 3. Docker イメージビルド・プッシュ

```bash
# ECRログイン
aws-vault exec shinyat -- aws ecr get-login-password \
  --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URI}

# 本番用Dockerイメージビルド
docker build --platform linux/amd64 -t ${ECR_REPOSITORY_NAME}:latest -f Dockerfile.prod .

# タグ付け
docker tag ${ECR_REPOSITORY_NAME}:latest ${ECR_URI}:latest

# プッシュ
docker push ${ECR_URI}:latest
```

### 4. RDS MySQLセットアップ

#### RDS インスタンス作成
```bash
# サブネットグループ作成（VPCのプライベートサブネット使用）
aws-vault exec shinyat -- aws rds create-db-subnet-group \
  --db-subnet-group-name ${PROJECT_NAME}-subnet-group \
  --db-subnet-group-description "Subnet group for Project Forest" \
  --subnet-ids subnet-xxxxx subnet-yyyyy  # プライベートサブネットID

# セキュリティグループ作成
export RDS_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-rds-sg \
  --description "Security group for Project Forest RDS" \
  --vpc-id vpc-xxxxx \
  --query 'GroupId' --output text)

# MySQL接続許可（ECSセキュリティグループから）
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_SG_ID} \
  --protocol tcp \
  --port 3306 \
  --source-group sg-xxxxx  # ECSのセキュリティグループID

# RDS作成
aws-vault exec shinyat -- aws rds create-db-instance \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username admin \
  --master-user-password "YourSecurePassword123!" \
  --allocated-storage 20 \
  --db-name project_forest \
  --vpc-security-group-ids ${RDS_SG_ID} \
  --db-subnet-group-name ${PROJECT_NAME}-subnet-group \
  --backup-retention-period 7 \
  --multi-az \
  --storage-encrypted \
  --no-publicly-accessible
```

#### データベース初期化
```bash
# RDSエンドポイント取得
export RDS_ENDPOINT=$(aws-vault exec shinyat -- aws rds describe-db-instances \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# データベース初期化（踏み台サーバーまたはVPN経由）
mysql -h ${RDS_ENDPOINT} -u admin -p project_forest < scripts/init-database.sql
```

### 5. AWS Secrets Manager設定

```bash
# データベース認証情報をSecrets Managerに保存
aws-vault exec shinyat -- aws secretsmanager create-secret \
  --name ${PROJECT_NAME}/database \
  --description "Database credentials for Project Forest" \
  --secret-string '{
    "host": "'${RDS_ENDPOINT}'",
    "port": "3306",
    "username": "admin",
    "password": "YourSecurePassword123!",
    "database": "project_forest"
  }'
```

### 6. ECS環境構築

#### IAM実行ロール作成
```bash
# 信頼ポリシー作成
cat > ecs-task-execution-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 実行ロール作成
aws-vault exec shinyat -- aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# ポリシー割り当て
aws-vault exec shinyat -- aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Secrets Manager読み取り権限追加
cat > secrets-manager-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:*:secret:${PROJECT_NAME}/database*"
    }
  ]
}
EOF

aws-vault exec shinyat -- aws iam put-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name SecretsManagerAccess \
  --policy-document file://secrets-manager-policy.json
```

#### ECSクラスタ作成
```bash
aws-vault exec shinyat -- aws ecs create-cluster \
  --cluster-name ${CLUSTER_NAME} \
  --capacity-providers FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1
```

#### タスク定義作成
```bash
cat > task-definition.json << EOF
{
  "family": "${TASK_DEFINITION_NAME}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::\${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "${PROJECT_NAME}-container",
      "image": "${ECR_URI}:latest",
      "essential": true,
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
          "name": "PORT",
          "value": "3000"
        }
      ],
      "secrets": [
        {
          "name": "DB_HOST",
          "valueFrom": "arn:aws:secretsmanager:${AWS_REGION}:\${AWS_ACCOUNT_ID}:secret:${PROJECT_NAME}/database:host::"
        },
        {
          "name": "DB_PORT",
          "valueFrom": "arn:aws:secretsmanager:${AWS_REGION}:\${AWS_ACCOUNT_ID}:secret:${PROJECT_NAME}/database:port::"
        },
        {
          "name": "DB_USER",
          "valueFrom": "arn:aws:secretsmanager:${AWS_REGION}:\${AWS_ACCOUNT_ID}:secret:${PROJECT_NAME}/database:username::"
        },
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:${AWS_REGION}:\${AWS_ACCOUNT_ID}:secret:${PROJECT_NAME}/database:password::"
        },
        {
          "name": "DB_NAME",
          "valueFrom": "arn:aws:secretsmanager:${AWS_REGION}:\${AWS_ACCOUNT_ID}:secret:${PROJECT_NAME}/database:database::"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${PROJECT_NAME}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 0
      }
    }
  ]
}
EOF

# AWSアカウントID取得
export AWS_ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)

# task-definition.jsonの\${AWS_ACCOUNT_ID}を実際のIDで置換
sed -i "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" task-definition.json

# CloudWatch Logsグループ作成
aws-vault exec shinyat -- aws logs create-log-group \
  --log-group-name "/ecs/${PROJECT_NAME}"

# タスク定義登録
aws-vault exec shinyat -- aws ecs register-task-definition \
  --cli-input-json file://task-definition.json
```

### 7. ALB設定

```bash
# Application Load Balancer作成
export ALB_ARN=$(aws-vault exec shinyat -- aws elbv2 create-load-balancer \
  --name ${PROJECT_NAME}-alb \
  --subnets subnet-xxxxx subnet-yyyyy \
  --security-groups sg-xxxxx \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# ターゲットグループ作成
export TG_ARN=$(aws-vault exec shinyat -- aws elbv2 create-target-group \
  --name ${PROJECT_NAME}-tg \
  --protocol HTTP \
  --port 3000 \
  --vpc-id vpc-xxxxx \
  --target-type ip \
  --health-check-enabled \
  --health-check-interval-seconds 30 \
  --health-check-path /api/health \
  --health-check-port traffic-port \
  --health-check-protocol HTTP \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# リスナー作成
aws-vault exec shinyat -- aws elbv2 create-listener \
  --load-balancer-arn ${ALB_ARN} \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN}
```

### 8. ECSサービス起動

```bash
aws-vault exec shinyat -- aws ecs create-service \
  --cluster ${CLUSTER_NAME} \
  --service-name ${SERVICE_NAME} \
  --task-definition ${TASK_DEFINITION_NAME} \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-xxxxx,subnet-yyyyy],
    securityGroups=[sg-xxxxx],
    assignPublicIp=DISABLED
  }" \
  --load-balancers "targetGroupArn=${TG_ARN},containerName=${PROJECT_NAME}-container,containerPort=3000" \
  --health-check-grace-period-seconds 300
```

## データベース接続設定

### 本番環境での環境変数

アプリケーションは以下の環境変数を使用します：

- `DB_HOST`: RDSエンドポイント
- `DB_PORT`: 3306
- `DB_USER`: データベースユーザー
- `DB_PASSWORD`: データベースパスワード
- `DB_NAME`: project_forest

これらはAWS Secrets Managerから自動的に取得されます。

### 接続プール設定

`lib/database.ts`で設定されている接続プール：

```typescript
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '3306'),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});
```

## 初期データ投入

### 方法1: SQLスクリプト実行

```bash
# RDS接続（踏み台サーバーまたはVPN経由）
mysql -h ${RDS_ENDPOINT} -u admin -p project_forest < scripts/init-database.sql
```

### 方法2: 管理画面での手動登録

1. ALBのDNS名でアプリケーションにアクセス
2. `/admin`パスで管理画面を開く
3. 各タブで初期データを登録：
   - キャラクター管理
   - タグ管理
   - 固有名詞管理
   - 禁止用語管理
   - スタイル設定

### 方法3: API経由での一括投入

```bash
# 管理画面用のサンプルスクリプト作成
cat > seed-data.sh << 'EOF'
#!/bin/bash

ALB_DNS="your-alb-dns-name"
BASE_URL="http://${ALB_DNS}"

# キャラクター登録
curl -X POST "${BASE_URL}/api/characters" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "protagonist",
    "display_name": "プロタゴニスト",
    "icon": "🎭",
    "description": "メインキャラクター。物語の主人公として登場します。"
  }'

# タグ登録
curl -X POST "${BASE_URL}/api/tags" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "character_name",
    "display_text": "{CHARACTER_NAME}",
    "icon": "👤",
    "description": "キャラクター名を動的に表示するタグ"
  }'
EOF

chmod +x seed-data.sh
./seed-data.sh
```

## 監視とログ

### CloudWatch Logs確認

```bash
# ログストリーム一覧
aws-vault exec shinyat -- aws logs describe-log-streams \
  --log-group-name "/ecs/${PROJECT_NAME}"

# 最新ログ取得
aws-vault exec shinyat -- aws logs tail "/ecs/${PROJECT_NAME}" --follow
```

### ヘルスチェック確認

```bash
# ALB DNS名取得
export ALB_DNS=$(aws-vault exec shinyat -- aws elbv2 describe-load-balancers \
  --load-balancer-arns ${ALB_ARN} \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# ヘルスチェック
curl http://${ALB_DNS}/api/health
```

## デプロイ後の確認事項

1. **アプリケーション起動確認**
   ```bash
   curl http://${ALB_DNS}/
   ```

2. **管理画面確認**
   ```bash
   curl http://${ALB_DNS}/admin
   ```

3. **データベース接続確認**
   ```bash
   curl http://${ALB_DNS}/api/health
   ```

4. **API動作確認**
   ```bash
   curl http://${ALB_DNS}/api/characters
   curl http://${ALB_DNS}/api/tags
   ```

## トラブルシューティング

### よくある問題

1. **タスクが起動しない**
   - CloudWatch Logsでエラー確認
   - セキュリティグループ設定確認
   - VPCエンドポイント設定確認

2. **データベース接続エラー**
   - RDSセキュリティグループ確認
   - Secrets Manager権限確認
   - VPC設定確認

3. **ヘルスチェック失敗**
   - アプリケーションログ確認
   - ヘルスチェックパス確認（`/api/health`）
   - ターゲットグループ設定確認

## 更新デプロイ

```bash
# 新しいイメージビルド・プッシュ
docker build --platform linux/amd64 -t ${ECR_REPOSITORY_NAME}:v2 -f Dockerfile.prod .
docker tag ${ECR_REPOSITORY_NAME}:v2 ${ECR_URI}:v2
docker push ${ECR_URI}:v2

# タスク定義更新（imageをv2に変更）
# サービス更新
aws-vault exec shinyat -- aws ecs update-service \
  --cluster ${CLUSTER_NAME} \
  --service ${SERVICE_NAME} \
  --task-definition ${TASK_DEFINITION_NAME}:2
```

このデプロイガイドに従って、本番環境でProject Forestアプリケーションを安全にデプロイできます。