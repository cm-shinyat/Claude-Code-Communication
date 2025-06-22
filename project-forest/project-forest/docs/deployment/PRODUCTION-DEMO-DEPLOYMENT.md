# Project Forest デモ環境構築ガイド（本格版）

お客様向けデモ環境を構築するための完全な手順書です。RDS、ALB、ECS、初期データ投入まで含む本格的な環境を構築します。

## 🎯 構築するアーキテクチャ

```
インターネット
    ↓
Route 53 (demo.project-forest.com)
    ↓
Application Load Balancer
    ↓
ECS Fargate (Auto Scaling)
    ↓
RDS MySQL (Multi-AZ)
```

## 📋 前提条件

- AWS アカウント（管理者権限）
- aws-vault 設定済み
- ドメイン名（例：project-forest.com）
- SSL証明書の作成権限

## 🚀 デプロイ手順

### ステップ 1: VPCとネットワーク構築

```bash
# 変数設定
REGION="ap-northeast-1"
PROJECT_NAME="project-forest-demo"
DOMAIN_NAME="demo1.cc.cm-ga.me"

# 専用VPCを作成
VPC_ID=$(aws-vault exec shinyat -- aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc}]" \
  --query "Vpc.VpcId" \
  --output text \
  --region $REGION)

echo "VPC ID: $VPC_ID"

# インターネットゲートウェイを作成・アタッチ
IGW_ID=$(aws-vault exec shinyat -- aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
  --query "InternetGateway.InternetGatewayId" \
  --output text \
  --region $REGION)

aws-vault exec shinyat -- aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID \
  --region $REGION

# パブリックサブネット作成（ALB用）
PUBLIC_SUBNET_1=$(aws-vault exec shinyat -- aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1a}]" \
  --query "Subnet.SubnetId" \
  --output text \
  --region $REGION)

PUBLIC_SUBNET_2=$(aws-vault exec shinyat -- aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ${REGION}c \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1c}]" \
  --query "Subnet.SubnetId" \
  --output text \
  --region $REGION)

# パブリックサブネットの設定
aws-vault exec shinyat -- aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_1 \
  --map-public-ip-on-launch \
  --region $REGION

aws-vault exec shinyat -- aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_2 \
  --map-public-ip-on-launch \
  --region $REGION

# プライベートサブネット作成（ECS・RDS用）
PRIVATE_SUBNET_1=$(aws-vault exec shinyat -- aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.11.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-1a}]" \
  --query "Subnet.SubnetId" \
  --output text \
  --region $REGION)

PRIVATE_SUBNET_2=$(aws-vault exec shinyat -- aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.12.0/24 \
  --availability-zone ${REGION}c \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-1c}]" \
  --query "Subnet.SubnetId" \
  --output text \
  --region $REGION)

# ルートテーブル作成（パブリック用）
ROUTE_TABLE_ID=$(aws-vault exec shinyat -- aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt}]" \
  --query "RouteTable.RouteTableId" \
  --output text \
  --region $REGION)

# インターネットゲートウェイへのルート追加
aws-vault exec shinyat -- aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $REGION

# パブリックサブネットをルートテーブルに関連付け
aws-vault exec shinyat -- aws ec2 associate-route-table \
  --subnet-id $PUBLIC_SUBNET_1 \
  --route-table-id $ROUTE_TABLE_ID \
  --region $REGION

aws-vault exec shinyat -- aws ec2 associate-route-table \
  --subnet-id $PUBLIC_SUBNET_2 \
  --route-table-id $ROUTE_TABLE_ID \
  --region $REGION

echo "ネットワーク構築完了"
echo "Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
echo "Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
```

### ステップ 2: セキュリティグループ作成

```bash
# ALB用セキュリティグループ
ALB_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-alb-sg \
  --description "Security group for ${PROJECT_NAME} ALB" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-alb-sg}]" \
  --query "GroupId" \
  --output text \
  --region $REGION)

# HTTP/HTTPS許可
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region $REGION

aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# ECS用セキュリティグループ
ECS_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-ecs-sg \
  --description "Security group for ${PROJECT_NAME} ECS" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-ecs-sg}]" \
  --query "GroupId" \
  --output text \
  --region $REGION)

# ALBからのアクセスのみ許可
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG_ID \
  --protocol tcp \
  --port 3000 \
  --source-group $ALB_SG_ID \
  --region $REGION

# RDS用セキュリティグループ
RDS_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-rds-sg \
  --description "Security group for ${PROJECT_NAME} RDS" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-rds-sg}]" \
  --query "GroupId" \
  --output text \
  --region $REGION)

# ECSからMySQLアクセスのみ許可
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $ECS_SG_ID \
  --region $REGION

echo "セキュリティグループ作成完了"
echo "ALB SG: $ALB_SG_ID"
echo "ECS SG: $ECS_SG_ID"
echo "RDS SG: $RDS_SG_ID"
```

### ステップ 3: RDSデータベース構築

```bash
# DBサブネットグループ作成
aws-vault exec shinyat -- aws rds create-db-subnet-group \
  --db-subnet-group-name ${PROJECT_NAME}-db-subnet-group \
  --db-subnet-group-description "DB subnet group for ${PROJECT_NAME}" \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --region $REGION

# RDSインスタンス作成
DB_PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-15)
echo "DB Password: $DB_PASSWORD"

aws-vault exec shinyat -- aws rds create-db-instance \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username admin \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 20 \
  --storage-type gp2 \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-subnet-group-name ${PROJECT_NAME}-db-subnet-group \
  --backup-retention-period 7 \
  --multi-az \
  --storage-encrypted \
  --db-name projectforest \
  --region $REGION

echo "RDS作成開始（10-15分かかります）..."

# RDS作成完了を待機
aws-vault exec shinyat -- aws rds wait db-instance-available \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --region $REGION

# エンドポイント取得
DB_ENDPOINT=$(aws-vault exec shinyat -- aws rds describe-db-instances \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text \
  --region $REGION)

echo "RDS構築完了"
echo "DB Endpoint: $DB_ENDPOINT"
```

### ステップ 4: SSL証明書作成

```bash
# SSL証明書をACMで発行
CERTIFICATE_ARN=$(aws-vault exec shinyat -- aws acm request-certificate \
  --domain-name $DOMAIN_NAME \
  --validation-method DNS \
  --region $REGION \
  --query "CertificateArn" \
  --output text)

echo "SSL証明書ARN: $CERTIFICATE_ARN"
echo "⚠️  DNS検証が必要です。AWS Console で ACM を確認し、CNAMEレコードをDNSに追加してください。"

# 証明書の検証完了を待機（手動DNS検証が必要）
echo "DNS検証完了後、Enterキーを押してください..."
read

aws-vault exec shinyat -- aws acm wait certificate-validated \
  --certificate-arn $CERTIFICATE_ARN \
  --region $REGION
```

### ステップ 5: Application Load Balancer作成

```bash
# ALB作成
ALB_ARN=$(aws-vault exec shinyat -- aws elbv2 create-load-balancer \
  --name ${PROJECT_NAME}-alb \
  --subnets $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 \
  --security-groups $ALB_SG_ID \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --tags Key=Name,Value=${PROJECT_NAME}-alb \
  --region $REGION \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text)

# ターゲットグループ作成
TARGET_GROUP_ARN=$(aws-vault exec shinyat -- aws elbv2 create-target-group \
  --name ${PROJECT_NAME}-tg \
  --protocol HTTP \
  --port 3000 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-enabled \
  --health-check-path /api/health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 10 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --matcher HttpCode=200 \
  --tags Key=Name,Value=${PROJECT_NAME}-tg \
  --region $REGION \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text)

# HTTPSリスナー作成
aws-vault exec shinyat -- aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=$CERTIFICATE_ARN \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
  --region $REGION

# HTTPからHTTPSへのリダイレクト
aws-vault exec shinyat -- aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
  --region $REGION

# ALBのDNS名取得
ALB_DNS=$(aws-vault exec shinyat -- aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --region $REGION \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo "ALB作成完了"
echo "ALB DNS: $ALB_DNS"
```

### ステップ 6: Route 53でDNS設定

```bash
# ホストゾーンID取得（事前にドメインのホストゾーンが必要）
HOSTED_ZONE_ID="Z06314681E638VGI0WCKJ"  # あなたのドメインのホストゾーンID

# Aレコード作成
aws-vault exec shinyat -- aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$DOMAIN_NAME\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"Z14GRHDCWA56QT\",
          \"DNSName\": \"$ALB_DNS\",
          \"EvaluateTargetHealth\": false
        }
      }
    }]
  }" \
  --region $REGION

echo "DNS設定完了: https://$DOMAIN_NAME"
```

### ステップ 7: Secrets Manager設定

```bash
# データベース認証情報をSecrets Managerに保存
SECRET_ARN=$(aws-vault exec shinyat -- aws secretsmanager create-secret \
  --name ${PROJECT_NAME}/database \
  --description "Database credentials for ${PROJECT_NAME}" \
  --secret-string "{
    \"username\": \"admin\",
    \"password\": \"$DB_PASSWORD\",
    \"engine\": \"mysql\",
    \"host\": \"$DB_ENDPOINT\",
    \"port\": 3306,
    \"dbname\": \"projectforest\"
  }" \
  --region $REGION \
  --query "ARN" \
  --output text)

echo "Secrets Manager設定完了: $SECRET_ARN"
```

### ステップ 8: IAMロール作成

```bash
# ECS実行ロール作成
aws-vault exec shinyat -- aws iam create-role \
  --role-name ${PROJECT_NAME}-execution-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' 2>/dev/null || echo "実行ロールは既に存在します"

# 必要なポリシーをアタッチ
aws-vault exec shinyat -- aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Secrets Managerアクセス用ポリシー作成
ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)

aws-vault exec shinyat -- aws iam create-policy \
  --policy-name ${PROJECT_NAME}-secrets-policy \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [
        \"secretsmanager:GetSecretValue\"
      ],
      \"Resource\": \"$SECRET_ARN\"
    }]
  }" 2>/dev/null || echo "ポリシーは既に存在します"

aws-vault exec shinyat -- aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-execution-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${PROJECT_NAME}-secrets-policy
```

### ステップ 9: ECSクラスターとタスク定義

```bash
# ECSクラスター作成
aws-vault exec shinyat -- aws ecs create-cluster \
  --cluster-name ${PROJECT_NAME}-cluster \
  --capacity-providers FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --region $REGION

# タスク定義作成
aws-vault exec shinyat -- aws ecs register-task-definition \
  --family ${PROJECT_NAME}-task \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 512 \
  --memory 1024 \
  --execution-role-arn arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-execution-role \
  --container-definitions "[
    {
      \"name\": \"project-forest\",
      \"image\": \"${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest\",
      \"portMappings\": [{
        \"containerPort\": 3000,
        \"protocol\": \"tcp\"
      }],
      \"essential\": true,
      \"environment\": [
        {\"name\": \"NODE_ENV\", \"value\": \"production\"},
        {\"name\": \"PORT\", \"value\": \"3000\"}
      ],
      \"secrets\": [
        {\"name\": \"DB_HOST\", \"valueFrom\": \"${SECRET_ARN}:host::\"},
        {\"name\": \"DB_USER\", \"valueFrom\": \"${SECRET_ARN}:username::\"},
        {\"name\": \"DB_PASSWORD\", \"valueFrom\": \"${SECRET_ARN}:password::\"},
        {\"name\": \"DB_NAME\", \"valueFrom\": \"${SECRET_ARN}:dbname::\"}
      ],
      \"logConfiguration\": {
        \"logDriver\": \"awslogs\",
        \"options\": {
          \"awslogs-group\": \"/ecs/${PROJECT_NAME}\",
          \"awslogs-region\": \"${REGION}\",
          \"awslogs-stream-prefix\": \"ecs\",
          \"awslogs-create-group\": \"true\"
        }
      }
    }
  ]" \
  --region $REGION
```

### ステップ 10: ECRイメージプッシュ

```bash
# ECRリポジトリ作成
aws-vault exec shinyat -- aws ecr create-repository \
  --repository-name project-forest \
  --region $REGION 2>/dev/null || echo "ECRリポジトリは既に存在します"

# ECRログイン
aws-vault exec shinyat -- aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Dockerイメージビルド（開発用 - ビルドエラー回避）
docker build -f infrastructure/docker/Dockerfile.dev -t project-forest:latest .

# タグ付けとプッシュ
docker tag project-forest:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest
```

### ステップ 11: データベース初期化

```bash
# 一時的なEC2インスタンスでデータベースセットアップ
# または、ECSタスクで初期化用コンテナを実行

# ECSタスクでデータベース初期化を実行
aws-vault exec shinyat -- aws ecs run-task \
  --cluster ${PROJECT_NAME}-cluster \
  --task-definition ${PROJECT_NAME}-task \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2],
    securityGroups=[$ECS_SG_ID],
    assignPublicIp=ENABLED
  }" \
  --overrides "{
    \"containerOverrides\": [{
      \"name\": \"project-forest\",
      \"command\": [\"npm\", \"run\", \"db:init\"]
    }]
  }" \
  --region $REGION
```

### ステップ 12: ECSサービス作成

```bash
# ECSサービス作成
aws-vault exec shinyat -- aws ecs create-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name ${PROJECT_NAME}-service \
  --task-definition ${PROJECT_NAME}-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={
    subnets=[$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2],
    securityGroups=[$ECS_SG_ID],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=project-forest,containerPort=3000" \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=50" \
  --region $REGION

echo "ECSサービス作成完了"
```

### ステップ 13: Auto Scaling設定

```bash
# Auto Scaling設定
aws-vault exec shinyat -- aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/${PROJECT_NAME}-cluster/${PROJECT_NAME}-service \
  --min-capacity 2 \
  --max-capacity 10 \
  --region $REGION

# スケーリングポリシー（CPU使用率ベース）
aws-vault exec shinyat -- aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/${PROJECT_NAME}-cluster/${PROJECT_NAME}-service \
  --policy-name ${PROJECT_NAME}-cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration "{
    \"TargetValue\": 70.0,
    \"PredefinedMetricSpecification\": {
      \"PredefinedMetricType\": \"ECSServiceAverageCPUUtilization\"
    },
    \"ScaleOutCooldown\": 300,
    \"ScaleInCooldown\": 300
  }" \
  --region $REGION
```

## 🎉 デプロイ完了確認

```bash
echo "🎉 デモ環境構築完了！"
echo ""
echo "=== アクセス情報 ==="
echo "デモサイトURL: https://$DOMAIN_NAME"
echo "データベース: $DB_ENDPOINT"
echo "ALB DNS: $ALB_DNS"
echo ""
echo "=== 管理コマンド ==="
echo "ログ確認: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow"
echo "サービス確認: aws-vault exec shinyat -- aws ecs describe-services --cluster ${PROJECT_NAME}-cluster --services ${PROJECT_NAME}-service"
echo ""
echo "=== ログイン情報 ==="
echo "管理者: admin@demo.com / password"
echo "デモユーザー: demo@demo.com / password"
```

## 📊 監視とメンテナンス

### CloudWatch設定

```bash
# ダッシュボード作成
aws-vault exec shinyat -- aws cloudwatch put-dashboard \
  --dashboard-name ${PROJECT_NAME}-dashboard \
  --dashboard-body "{
    \"widgets\": [
      {
        \"type\": \"metric\",
        \"properties\": {
          \"metrics\": [
            [\"AWS/ECS\", \"CPUUtilization\", \"ServiceName\", \"${PROJECT_NAME}-service\", \"ClusterName\", \"${PROJECT_NAME}-cluster\"],
            [\"AWS/ECS\", \"MemoryUtilization\", \"ServiceName\", \"${PROJECT_NAME}-service\", \"ClusterName\", \"${PROJECT_NAME}-cluster\"]
          ],
          \"period\": 300,
          \"stat\": \"Average\",
          \"region\": \"${REGION}\",
          \"title\": \"ECS Metrics\"
        }
      }
    ]
  }"
```

### バックアップ設定

```bash
# RDSの自動バックアップは既に有効（backup-retention-period 7）

# S3バケット作成（ファイルアップロード用）
aws-vault exec shinyat -- aws s3 mb s3://${PROJECT_NAME}-uploads-$(date +%Y%m%d) --region $REGION
```

## 💰 コスト見積もり

**月額料金概算（東京リージョン）:**
- ALB: $22.50
- ECS Fargate (2タスク): $30.00
- RDS (db.t3.micro Multi-AZ): $28.00
- NAT Gateway: $32.40
- ECR: $1.00
- Route 53: $0.50
- **合計: 約$114/月**

## 🛠️ トラブルシューティング

### よくある問題

1. **SSL証明書の検証**
   ```bash
   aws-vault exec shinyat -- aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN
   ```

2. **ECSタスクが起動しない**
   ```bash
   aws-vault exec shinyat -- aws ecs describe-services --cluster ${PROJECT_NAME}-cluster --services ${PROJECT_NAME}-service
   ```

3. **データベース接続エラー**
   ```bash
   aws-vault exec shinyat -- aws rds describe-db-instances --db-instance-identifier ${PROJECT_NAME}-db
   ```

これで本格的なデモ環境が構築できます！