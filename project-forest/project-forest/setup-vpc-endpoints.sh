#!/usr/bin/env zsh
# VPCエンドポイント設定スクリプト
# Secrets Manager、ECR、CloudWatch Logs用のVPCエンドポイントを作成

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

echo "${BLUE}🔗 VPCエンドポイント設定を開始します${NC}"
echo ""

# VPC情報取得
VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION)

PRIVATE_SUBNET_1=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-private-1a" \
  --query "Subnets[0].SubnetId" \
  --output text \
  --region $REGION)

PRIVATE_SUBNET_2=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-private-1c" \
  --query "Subnets[0].SubnetId" \
  --output text \
  --region $REGION)

echo "VPC ID: $VPC_ID"
echo "Private Subnet 1: $PRIVATE_SUBNET_1"
echo "Private Subnet 2: $PRIVATE_SUBNET_2"

# VPCエンドポイント用セキュリティグループ作成
echo ""
echo "${YELLOW}🛡️  ステップ 1: VPCエンドポイント用セキュリティグループ作成${NC}"
VPC_ENDPOINT_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-vpc-endpoint-sg \
  --description "Security group for VPC endpoints" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc-endpoint-sg}]" \
  --query "GroupId" \
  --output text \
  --region $REGION 2>/dev/null || \
aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PROJECT_NAME}-vpc-endpoint-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION)

echo "VPCエンドポイント用セキュリティグループ: $VPC_ENDPOINT_SG_ID"

# HTTPS (443) をVPC CIDRから許可
echo "HTTPS (443) アクセス許可設定中..."
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $VPC_ENDPOINT_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 10.0.0.0/16 \
  --region $REGION 2>/dev/null || echo "ルールは既に存在します"

# ECSセキュリティグループにVPCエンドポイントへのアウトバウンドアクセス許可
ECS_SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PROJECT_NAME}-ecs-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION)

echo ""
echo "${YELLOW}🔓 ステップ 2: ECSセキュリティグループにアウトバウンドルール追加${NC}"
aws-vault exec shinyat -- aws ec2 authorize-security-group-egress \
  --group-id $ECS_SG_ID \
  --protocol tcp \
  --port 443 \
  --source-group $VPC_ENDPOINT_SG_ID \
  --region $REGION 2>/dev/null || echo "ルールは既に存在します"

# 1. Secrets Manager VPCエンドポイント作成
echo ""
echo "${YELLOW}🔐 ステップ 3: Secrets Manager VPCエンドポイント作成${NC}"
SECRETS_MANAGER_ENDPOINT=$(aws-vault exec shinyat -- aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.${REGION}.secretsmanager \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --security-group-ids $VPC_ENDPOINT_SG_ID \
  --private-dns-enabled \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT_NAME}-secrets-manager-endpoint}]" \
  --region $REGION \
  --query "VpcEndpoint.VpcEndpointId" \
  --output text 2>/dev/null || \
aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.secretsmanager" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION)

echo "Secrets Manager VPCエンドポイント: $SECRETS_MANAGER_ENDPOINT"

# 2. ECR DKR VPCエンドポイント作成
echo ""
echo "${YELLOW}📦 ステップ 4: ECR DKR VPCエンドポイント作成${NC}"
ECR_DKR_ENDPOINT=$(aws-vault exec shinyat -- aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.${REGION}.ecr.dkr \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --security-group-ids $VPC_ENDPOINT_SG_ID \
  --private-dns-enabled \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT_NAME}-ecr-dkr-endpoint}]" \
  --region $REGION \
  --query "VpcEndpoint.VpcEndpointId" \
  --output text 2>/dev/null || \
aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.ecr.dkr" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION)

echo "ECR DKR VPCエンドポイント: $ECR_DKR_ENDPOINT"

# 3. ECR API VPCエンドポイント作成
echo ""
echo "${YELLOW}📦 ステップ 5: ECR API VPCエンドポイント作成${NC}"
ECR_API_ENDPOINT=$(aws-vault exec shinyat -- aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.${REGION}.ecr.api \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --security-group-ids $VPC_ENDPOINT_SG_ID \
  --private-dns-enabled \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT_NAME}-ecr-api-endpoint}]" \
  --region $REGION \
  --query "VpcEndpoint.VpcEndpointId" \
  --output text 2>/dev/null || \
aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.ecr.api" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION)

echo "ECR API VPCエンドポイント: $ECR_API_ENDPOINT"

# 4. CloudWatch Logs VPCエンドポイント作成
echo ""
echo "${YELLOW}📝 ステップ 6: CloudWatch Logs VPCエンドポイント作成${NC}"
LOGS_ENDPOINT=$(aws-vault exec shinyat -- aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.${REGION}.logs \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --security-group-ids $VPC_ENDPOINT_SG_ID \
  --private-dns-enabled \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT_NAME}-logs-endpoint}]" \
  --region $REGION \
  --query "VpcEndpoint.VpcEndpointId" \
  --output text 2>/dev/null || \
aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.logs" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION)

echo "CloudWatch Logs VPCエンドポイント: $LOGS_ENDPOINT"

# 5. S3 Gateway VPCエンドポイント作成（ECRのレイヤー取得用）
echo ""
echo "${YELLOW}🪣 ステップ 7: S3 Gateway VPCエンドポイント作成${NC}"

# プライベートサブネットのルートテーブル取得
PRIVATE_ROUTE_TABLES=$(aws-vault exec shinyat -- aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[?Associations[?SubnetId=='$PRIVATE_SUBNET_1' || SubnetId=='$PRIVATE_SUBNET_2']].RouteTableId" \
  --output text \
  --region $REGION)

S3_ENDPOINT=$(aws-vault exec shinyat -- aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.${REGION}.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids $PRIVATE_ROUTE_TABLES \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT_NAME}-s3-endpoint}]" \
  --region $REGION \
  --query "VpcEndpoint.VpcEndpointId" \
  --output text 2>/dev/null || \
aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.s3" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION)

echo "S3 Gateway VPCエンドポイント: $S3_ENDPOINT"

# 6. VPCエンドポイントの状態確認
echo ""
echo "${YELLOW}⏳ ステップ 8: VPCエンドポイント状態確認${NC}"
echo "VPCエンドポイントの作成完了を待機中..."
sleep 60

# 各エンドポイントの状態確認
echo ""
echo "=== VPCエンドポイント状態 ==="
for ENDPOINT_ID in $SECRETS_MANAGER_ENDPOINT $ECR_DKR_ENDPOINT $ECR_API_ENDPOINT $LOGS_ENDPOINT $S3_ENDPOINT; do
  if [[ "$ENDPOINT_ID" != "None" ]] && [[ -n "$ENDPOINT_ID" ]]; then
    STATE=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
      --vpc-endpoint-ids $ENDPOINT_ID \
      --query "VpcEndpoints[0].State" \
      --output text \
      --region $REGION 2>/dev/null || echo "Unknown")
    echo "エンドポイント $ENDPOINT_ID: $STATE"
  fi
done

echo ""
echo "${GREEN}✅ VPCエンドポイント設定完了${NC}"
echo ""
echo "=== 設定されたVPCエンドポイント ==="
echo "• Secrets Manager: $SECRETS_MANAGER_ENDPOINT"
echo "• ECR DKR: $ECR_DKR_ENDPOINT"  
echo "• ECR API: $ECR_API_ENDPOINT"
echo "• CloudWatch Logs: $LOGS_ENDPOINT"
echo "• S3 Gateway: $S3_ENDPOINT"
echo ""
echo "${YELLOW}💡 次のステップ: ECSサービスを再起動してください${NC}"
echo "./restart-ecs-service.sh"