#!/usr/bin/env zsh
# Project Forest 本格デモ環境 完全自動デプロイスクリプト
# ALB、RDS、SSL証明書、Auto Scalingを含む本番レベルの環境を構築

set -e

# 色の定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 設定変数
REGION="ap-northeast-1"
PROJECT_NAME="project-forest-demo"
DOMAIN_NAME="demo.project-forest.com"  # 変更が必要
HOSTED_ZONE_ID="Z1234567890123"        # 変更が必要

echo "${BLUE}🎯 Project Forest 本格デモ環境構築を開始します${NC}"
echo ""
echo "=== 設定情報 ==="
echo "プロジェクト名: $PROJECT_NAME"
echo "ドメイン名: $DOMAIN_NAME"
echo "リージョン: $REGION"
echo ""

# アカウントID取得
ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# 確認プロンプト
echo "${YELLOW}⚠️  この操作は以下のAWSリソースを作成します：${NC}"
echo "- VPC、サブネット、IGW、ルートテーブル"
echo "- RDS MySQL (Multi-AZ)"
echo "- Application Load Balancer"
echo "- ECS Fargate クラスター・サービス"
echo "- SSL証明書 (ACM)"
echo "- Route 53 DNSレコード"
echo "- IAMロール・ポリシー"
echo ""
echo "${YELLOW}月額約$114の料金が発生します。続行しますか？ (y/N)${NC}"
read -r CONFIRM
if [[ "$CONFIRM" != "y" ]] && [[ "$CONFIRM" != "Y" ]]; then
    echo "デプロイをキャンセルしました"
    exit 0
fi

echo ""
echo "${YELLOW}🏗️  ステップ 1: VPCとネットワーク構築${NC}"

# VPC作成
echo "VPC作成中..."
VPC_ID=$(aws-vault exec shinyat -- aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc}]" \
  --query "Vpc.VpcId" \
  --output text \
  --region $REGION)

echo "VPC ID: $VPC_ID"

# インターネットゲートウェイ作成・アタッチ
echo "インターネットゲートウェイ作成中..."
IGW_ID=$(aws-vault exec shinyat -- aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
  --query "InternetGateway.InternetGatewayId" \
  --output text \
  --region $REGION)

aws-vault exec shinyat -- aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID \
  --region $REGION

# パブリックサブネット作成
echo "パブリックサブネット作成中..."
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

# プライベートサブネット作成
echo "プライベートサブネット作成中..."
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

# ルートテーブル作成
echo "ルートテーブル作成中..."
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

# サブネットをルートテーブルに関連付け
aws-vault exec shinyat -- aws ec2 associate-route-table \
  --subnet-id $PUBLIC_SUBNET_1 \
  --route-table-id $ROUTE_TABLE_ID \
  --region $REGION

aws-vault exec shinyat -- aws ec2 associate-route-table \
  --subnet-id $PUBLIC_SUBNET_2 \
  --route-table-id $ROUTE_TABLE_ID \
  --region $REGION

echo "${GREEN}✅ ネットワーク構築完了${NC}"
echo "Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
echo "Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"

echo ""
echo "${YELLOW}🛡️  ステップ 2: セキュリティグループ作成${NC}"

# ALB用セキュリティグループ
echo "ALB用セキュリティグループ作成中..."
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
echo "ECS用セキュリティグループ作成中..."
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
echo "RDS用セキュリティグループ作成中..."
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

echo "${GREEN}✅ セキュリティグループ作成完了${NC}"
echo "ALB SG: $ALB_SG_ID"
echo "ECS SG: $ECS_SG_ID"
echo "RDS SG: $RDS_SG_ID"

echo ""
echo "${YELLOW}🗄️  ステップ 3: RDSデータベース構築${NC}"

# DBサブネットグループ作成
echo "DBサブネットグループ作成中..."
aws-vault exec shinyat -- aws rds create-db-subnet-group \
  --db-subnet-group-name ${PROJECT_NAME}-db-subnet-group \
  --db-subnet-group-description "DB subnet group for ${PROJECT_NAME}" \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --region $REGION

# パスワード生成
DB_PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-15)
echo "DB Password: $DB_PASSWORD"

# RDSインスタンス作成
echo "RDSインスタンス作成中（10-15分かかります）..."
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

# RDS作成完了を待機
echo "RDS作成完了を待機中..."
aws-vault exec shinyat -- aws rds wait db-instance-available \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --region $REGION

# エンドポイント取得
DB_ENDPOINT=$(aws-vault exec shinyat -- aws rds describe-db-instances \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text \
  --region $REGION)

echo "${GREEN}✅ RDS構築完了${NC}"
echo "DB Endpoint: $DB_ENDPOINT"

echo ""
echo "${YELLOW}🔒 ステップ 4: SSL証明書作成${NC}"

# SSL証明書をACMで発行
echo "SSL証明書を発行中..."
CERTIFICATE_ARN=$(aws-vault exec shinyat -- aws acm request-certificate \
  --domain-name $DOMAIN_NAME \
  --validation-method DNS \
  --region $REGION \
  --query "CertificateArn" \
  --output text)

echo "SSL証明書ARN: $CERTIFICATE_ARN"
echo "${YELLOW}⚠️  DNS検証が必要です。AWS Console で ACM を確認し、CNAMEレコードをDNSに追加してください。${NC}"

# 手動で検証完了を待機
echo "${YELLOW}DNS検証完了後、Enterキーを押してください...${NC}"
read

echo "証明書の検証完了を待機中..."
aws-vault exec shinyat -- aws acm wait certificate-validated \
  --certificate-arn $CERTIFICATE_ARN \
  --region $REGION

echo "${GREEN}✅ SSL証明書発行完了${NC}"

echo ""
echo "${YELLOW}⚖️  ステップ 5: Application Load Balancer作成${NC}"

# ALB作成
echo "ALB作成中..."
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
echo "ターゲットグループ作成中..."
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
echo "HTTPSリスナー作成中..."
aws-vault exec shinyat -- aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=$CERTIFICATE_ARN \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
  --region $REGION

# HTTPからHTTPSへのリダイレクト
echo "HTTPリダイレクト設定中..."
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

echo "${GREEN}✅ ALB作成完了${NC}"
echo "ALB DNS: $ALB_DNS"

echo ""
echo "${YELLOW}🌐 ステップ 6: Route 53でDNS設定${NC}"

# Aレコード作成
echo "Route 53 Aレコード作成中..."
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

echo "${GREEN}✅ DNS設定完了: https://$DOMAIN_NAME${NC}"

echo ""
echo "${YELLOW}🔐 ステップ 7: Secrets Manager設定${NC}"

# データベース認証情報をSecrets Managerに保存
echo "Secrets Manager設定中..."
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

echo "${GREEN}✅ Secrets Manager設定完了: $SECRET_ARN${NC}"

echo ""
echo "${YELLOW}👤 ステップ 8: IAMロール作成${NC}"

# ECS実行ロール作成
echo "ECS実行ロール作成中..."
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

echo "${GREEN}✅ IAMロール作成完了${NC}"

echo ""
echo "${YELLOW}📦 ステップ 9: ECRとDockerイメージ${NC}"

# ECRリポジトリ作成
echo "ECRリポジトリ作成中..."
aws-vault exec shinyat -- aws ecr create-repository \
  --repository-name project-forest \
  --region $REGION 2>/dev/null || echo "ECRリポジトリは既に存在します"

# ECRログイン
echo "ECRにログイン中..."
aws-vault exec shinyat -- aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Dockerイメージビルド（開発用 - ビルドエラー回避）
echo "Dockerイメージビルド中..."
docker build -f infrastructure/docker/Dockerfile.dev -t project-forest:latest .

# タグ付けとプッシュ
echo "イメージプッシュ中..."
docker tag project-forest:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest

echo "${GREEN}✅ ECRプッシュ完了${NC}"

echo ""
echo "${YELLOW}🚀 ステップ 10: ECSクラスターとタスク定義${NC}"

# ECSクラスター作成
echo "ECSクラスター作成中..."
aws-vault exec shinyat -- aws ecs create-cluster \
  --cluster-name ${PROJECT_NAME}-cluster \
  --capacity-providers FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --region $REGION

# CloudWatchログループ作成
echo "CloudWatchログループ作成中..."
aws-vault exec shinyat -- aws logs create-log-group \
  --log-group-name /ecs/${PROJECT_NAME} \
  --region $REGION 2>/dev/null || true

# タスク定義作成
echo "タスク定義作成中..."
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

echo "${GREEN}✅ ECSクラスター・タスク定義作成完了${NC}"

echo ""
echo "${YELLOW}🎯 ステップ 11: ECSサービス作成${NC}"

# ECSサービス作成
echo "ECSサービス作成中..."
aws-vault exec shinyat -- aws ecs create-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name ${PROJECT_NAME}-service \
  --task-definition ${PROJECT_NAME}-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={
    subnets=[$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2],
    securityGroups=[$ECS_SG_ID],
    assignPublicIp=DISABLED
  }" \
  --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=project-forest,containerPort=3000" \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=50" \
  --region $REGION

echo "${GREEN}✅ ECSサービス作成完了${NC}"

echo ""
echo "${YELLOW}📈 ステップ 12: Auto Scaling設定${NC}"

# Auto Scaling設定
echo "Auto Scaling設定中..."
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

echo "${GREEN}✅ Auto Scaling設定完了${NC}"

echo ""
echo "${BLUE}🎉 デモ環境構築完了！${NC}"
echo ""
echo "=== アクセス情報 ==="
echo "デモサイトURL: ${GREEN}https://$DOMAIN_NAME${NC}"
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
echo ""
echo "${YELLOW}⚠️  注意: 月額約$114の料金が発生します${NC}"
echo "${YELLOW}💡 リソース削除は CLEANUP-PRODUCTION-DEMO.md の手順に従ってください${NC}"

# 設定情報をファイルに保存
cat > "${PROJECT_NAME}-deployment-info.txt" << EOF
Project Forest Demo Environment Deployment Info
================================================

Deployment Date: $(date)
Project Name: $PROJECT_NAME
Domain: $DOMAIN_NAME
Region: $REGION

Resource IDs:
- VPC ID: $VPC_ID
- ALB ARN: $ALB_ARN
- RDS Endpoint: $DB_ENDPOINT
- Secret ARN: $SECRET_ARN
- Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2
- Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2
- Security Groups: ALB($ALB_SG_ID), ECS($ECS_SG_ID), RDS($RDS_SG_ID)

Access URL: https://$DOMAIN_NAME
EOF

echo ""
echo "${GREEN}✅ 設定情報を ${PROJECT_NAME}-deployment-info.txt に保存しました${NC}"