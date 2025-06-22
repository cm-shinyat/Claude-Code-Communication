#!/bin/bash
# Project Forest 開発環境への完全自動デプロイスクリプト

set -e

# 色の定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🚀 Project Forest 開発環境デプロイを開始します${NC}"

# ステップ 0: 事前準備
echo -e "${YELLOW}📋 ステップ 0: 事前準備${NC}"
ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
REGION="ap-northeast-1"

# ステップ 1: Dockerイメージのビルド
echo -e "${YELLOW}🏗️  ステップ 1: Dockerイメージのビルド${NC}"
docker build -f infrastructure/docker/Dockerfile.dev -t project-forest:latest .

# ステップ 2: ECRリポジトリの作成
echo -e "${YELLOW}📦 ステップ 2: ECRリポジトリの確認・作成${NC}"
aws-vault exec shinyat -- aws ecr describe-repositories \
  --repository-names project-forest \
  --region $REGION 2>/dev/null || \
aws-vault exec shinyat -- aws ecr create-repository \
  --repository-name project-forest \
  --region $REGION

# ステップ 3: ECRへのログインとプッシュ
echo -e "${YELLOW}🔐 ステップ 3: ECRへのログインとイメージプッシュ${NC}"
aws-vault exec shinyat -- aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

docker tag project-forest:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest

# ステップ 4: CloudWatchログループの作成
echo -e "${YELLOW}📝 ステップ 4: CloudWatchログループの作成${NC}"
aws-vault exec shinyat -- aws logs create-log-group \
  --log-group-name /ecs/project-forest-dev \
  --region $REGION 2>/dev/null || true

# ステップ 5: タスク定義の登録
echo -e "${YELLOW}📋 ステップ 5: ECSタスク定義の登録${NC}"
aws-vault exec shinyat -- aws ecs register-task-definition \
  --family "project-forest-dev" \
  --network-mode "awsvpc" \
  --requires-compatibilities "FARGATE" \
  --cpu "256" \
  --memory "512" \
  --execution-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole" \
  --container-definitions "[
    {
      \"name\": \"project-forest\",
      \"image\": \"${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:latest\",
      \"portMappings\": [
        {
          \"containerPort\": 3000,
          \"protocol\": \"tcp\"
        }
      ],
      \"essential\": true,
      \"environment\": [
        {\"name\": \"NODE_ENV\", \"value\": \"development\"},
        {\"name\": \"PORT\", \"value\": \"3000\"},
        {\"name\": \"DB_HOST\", \"value\": \"localhost\"},
        {\"name\": \"DB_USER\", \"value\": \"root\"},
        {\"name\": \"DB_PASSWORD\", \"value\": \"password\"},
        {\"name\": \"DB_NAME\", \"value\": \"project_forest_dev\"}
      ],
      \"logConfiguration\": {
        \"logDriver\": \"awslogs\",
        \"options\": {
          \"awslogs-group\": \"/ecs/project-forest-dev\",
          \"awslogs-region\": \"${REGION}\",
          \"awslogs-stream-prefix\": \"ecs\"
        }
      }
    }
  ]" \
  --region $REGION > /dev/null

# ステップ 6: ECSクラスターの確認・作成
echo -e "${YELLOW}🎯 ステップ 6: ECSクラスターの確認・作成${NC}"
aws-vault exec shinyat -- aws ecs create-cluster \
  --cluster-name default \
  --region $REGION 2>/dev/null || true

# ステップ 7: VPC情報の取得
echo -e "${YELLOW}🌐 ステップ 7: VPC情報の取得${NC}"
VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION)
echo "VPC ID: $VPC_ID"

# サブネット取得
SUBNET_1=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=${REGION}a" \
  --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" \
  --output text \
  --region $REGION | head -1)

SUBNET_2=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=${REGION}c" \
  --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" \
  --output text \
  --region $REGION | head -1)

echo "Subnets: $SUBNET_1, $SUBNET_2"

# セキュリティグループの作成・取得
SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=project-forest-dev-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION 2>/dev/null)

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
  SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
    --group-name project-forest-dev-sg \
    --description "Security group for Project Forest dev" \
    --vpc-id $VPC_ID \
    --query "GroupId" \
    --output text \
    --region $REGION)
  
  # 現在のIPアドレスを取得
  MY_IP=$(curl -s https://checkip.amazonaws.com)
  echo "Your IP: $MY_IP"
  
  # ポート3000を自分のIPからのみ許可
  aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr ${MY_IP}/32 \
    --region $REGION \
    --group-rule-description "Allow port 3000 from my IP for development"
fi

echo "Security Group ID: $SG_ID"

# ステップ 8: ECSサービスの作成または更新
echo -e "${YELLOW}🚀 ステップ 8: ECSサービスの作成または更新${NC}"

# 既存のサービスを確認
SERVICE_EXISTS=$(aws-vault exec shinyat -- aws ecs describe-services \
  --cluster default \
  --services project-forest-dev \
  --region $REGION \
  --query "services[?status=='ACTIVE'].serviceName" \
  --output text 2>/dev/null)

if [ -z "$SERVICE_EXISTS" ]; then
  # サービスを作成
  aws-vault exec shinyat -- aws ecs create-service \
    --cluster default \
    --service-name project-forest-dev \
    --task-definition project-forest-dev \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={
      subnets=[\"$SUBNET_1\",\"$SUBNET_2\"],
      securityGroups=[\"$SG_ID\"],
      assignPublicIp=\"ENABLED\"
    }" \
    --region $REGION > /dev/null
else
  # サービスを更新
  aws-vault exec shinyat -- aws ecs update-service \
    --cluster default \
    --service project-forest-dev \
    --task-definition project-forest-dev \
    --force-new-deployment \
    --region $REGION > /dev/null
fi

# ステップ 9: デプロイの確認
echo -e "${YELLOW}✅ ステップ 9: デプロイの確認${NC}"
echo "サービスが起動するまで待機中..."
sleep 30

# タスクの状態を確認
TASK_ARN=$(aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster default \
  --service-name project-forest-dev \
  --query "taskArns[0]" \
  --output text \
  --region $REGION)

if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
  # タスクの詳細情報を取得
  TASK_DETAILS=$(aws-vault exec shinyat -- aws ecs describe-tasks \
    --cluster default \
    --tasks $TASK_ARN \
    --region $REGION)
  
  # ENIのIDを取得
  ENI_ID=$(echo $TASK_DETAILS | jq -r '.tasks[0].attachments[0].details[] | select(.name=="networkInterfaceId") | .value')
  
  if [ -n "$ENI_ID" ] && [ "$ENI_ID" != "null" ]; then
    # パブリックIPを取得
    PUBLIC_IP=$(aws-vault exec shinyat -- aws ec2 describe-network-interfaces \
      --network-interface-ids $ENI_ID \
      --query "NetworkInterfaces[0].Association.PublicIp" \
      --output text \
      --region $REGION 2>/dev/null)
    
    if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
      echo -e "${GREEN}✅ デプロイ完了！${NC}"
      echo -e "${GREEN}アプリケーションURL: http://$PUBLIC_IP:3000${NC}"
    else
      echo -e "${YELLOW}⚠️  パブリックIPの取得中...しばらくお待ちください${NC}"
    fi
  fi
else
  echo -e "${YELLOW}⚠️  タスクが起動中です。以下のコマンドでログを確認してください：${NC}"
  echo "aws-vault exec shinyat -- aws logs tail /ecs/project-forest-dev --follow"
fi

echo -e "${GREEN}✅ デプロイスクリプト完了！${NC}"