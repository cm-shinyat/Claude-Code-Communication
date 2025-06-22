#!/usr/bin/env zsh
# VPCエンドポイント作成修正スクリプト

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

echo "${BLUE}🔧 VPCエンドポイント作成問題の修正${NC}"
echo ""

# VPC情報取得
VPC_ID="vpc-0eb889d242976f7c2"
PRIVATE_SUBNET_1="subnet-045327644d0d5e5df"
PRIVATE_SUBNET_2="subnet-068d374080c7f3de6"

# VPCエンドポイント用セキュリティグループ確認
VPC_ENDPOINT_SG_ID="sg-0503d4febe9942e05"

echo "VPC ID: $VPC_ID"
echo "Private Subnet 1: $PRIVATE_SUBNET_1"
echo "Private Subnet 2: $PRIVATE_SUBNET_2"
echo "VPCエンドポイント SG: $VPC_ENDPOINT_SG_ID"

# 詳細なエラー情報でVPCエンドポイント作成を試行
echo ""
echo "${YELLOW}🔐 Secrets Manager VPCエンドポイント作成（詳細）${NC}"

# まず既存のエンドポイントを確認
EXISTING_SECRETS=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.secretsmanager" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION 2>/dev/null)

if [[ "$EXISTING_SECRETS" != "None" ]] && [[ -n "$EXISTING_SECRETS" ]]; then
  echo "既存のSecrets Manager VPCエンドポイントが見つかりました: $EXISTING_SECRETS"
  SECRETS_MANAGER_ENDPOINT="$EXISTING_SECRETS"
else
  echo "新しいSecrets Manager VPCエンドポイントを作成中..."
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
    --output text 2>&1)
  
  if [[ $? -ne 0 ]]; then
    echo "${RED}❌ Secrets Manager VPCエンドポイント作成失敗:${NC}"
    echo "$SECRETS_MANAGER_ENDPOINT"
  else
    echo "${GREEN}✅ Secrets Manager VPCエンドポイント作成成功: $SECRETS_MANAGER_ENDPOINT${NC}"
  fi
fi

# ECR DKR VPCエンドポイント
echo ""
echo "${YELLOW}📦 ECR DKR VPCエンドポイント作成${NC}"

EXISTING_ECR_DKR=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.ecr.dkr" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION 2>/dev/null)

if [[ "$EXISTING_ECR_DKR" != "None" ]] && [[ -n "$EXISTING_ECR_DKR" ]]; then
  echo "既存のECR DKR VPCエンドポイントが見つかりました: $EXISTING_ECR_DKR"
  ECR_DKR_ENDPOINT="$EXISTING_ECR_DKR"
else
  echo "新しいECR DKR VPCエンドポイントを作成中..."
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
    --output text 2>&1)
  
  if [[ $? -ne 0 ]]; then
    echo "${RED}❌ ECR DKR VPCエンドポイント作成失敗:${NC}"
    echo "$ECR_DKR_ENDPOINT"
  else
    echo "${GREEN}✅ ECR DKR VPCエンドポイント作成成功: $ECR_DKR_ENDPOINT${NC}"
  fi
fi

# ECR API VPCエンドポイント
echo ""
echo "${YELLOW}📦 ECR API VPCエンドポイント作成${NC}"

EXISTING_ECR_API=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.ecr.api" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION 2>/dev/null)

if [[ "$EXISTING_ECR_API" != "None" ]] && [[ -n "$EXISTING_ECR_API" ]]; then
  echo "既存のECR API VPCエンドポイントが見つかりました: $EXISTING_ECR_API"
  ECR_API_ENDPOINT="$EXISTING_ECR_API"
else
  echo "新しいECR API VPCエンドポイントを作成中..."
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
    --output text 2>&1)
  
  if [[ $? -ne 0 ]]; then
    echo "${RED}❌ ECR API VPCエンドポイント作成失敗:${NC}"
    echo "$ECR_API_ENDPOINT"
  else
    echo "${GREEN}✅ ECR API VPCエンドポイント作成成功: $ECR_API_ENDPOINT${NC}"
  fi
fi

# CloudWatch Logs VPCエンドポイント
echo ""
echo "${YELLOW}📝 CloudWatch Logs VPCエンドポイント作成${NC}"

EXISTING_LOGS=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.${REGION}.logs" "Name=vpc-id,Values=$VPC_ID" \
  --query "VpcEndpoints[0].VpcEndpointId" \
  --output text \
  --region $REGION 2>/dev/null)

if [[ "$EXISTING_LOGS" != "None" ]] && [[ -n "$EXISTING_LOGS" ]]; then
  echo "既存のCloudWatch Logs VPCエンドポイントが見つかりました: $EXISTING_LOGS"
  LOGS_ENDPOINT="$EXISTING_LOGS"
else
  echo "新しいCloudWatch Logs VPCエンドポイントを作成中..."
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
    --output text 2>&1)
  
  if [[ $? -ne 0 ]]; then
    echo "${RED}❌ CloudWatch Logs VPCエンドポイント作成失敗:${NC}"
    echo "$LOGS_ENDPOINT"
  else
    echo "${GREEN}✅ CloudWatch Logs VPCエンドポイント作成成功: $LOGS_ENDPOINT${NC}"
  fi
fi

# 利用可能サービスの確認
echo ""
echo "${YELLOW}🔍 利用可能なVPCエンドポイントサービス確認${NC}"
echo "利用可能なサービス一覧:"
aws-vault exec shinyat -- aws ec2 describe-vpc-endpoint-services \
  --region $REGION \
  --query "ServiceNames[?contains(@, 'secretsmanager') || contains(@, 'ecr') || contains(@, 'logs')]" \
  --output table

# セキュリティグループの詳細確認
echo ""
echo "${YELLOW}🛡️  セキュリティグループ設定確認${NC}"
aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $VPC_ENDPOINT_SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].{GroupId:GroupId,InboundRules:IpPermissions,OutboundRules:IpPermissionsEgress}" \
  --output table

echo ""
echo "${BLUE}💡 手動作成も可能です${NC}"
echo "AWSコンソールでVPCエンドポイントを作成する場合："
echo "1. VPC > エンドポイント > エンドポイントを作成"
echo "2. サービスカテゴリ: AWS サービス"
echo "3. サービス名: com.amazonaws.ap-northeast-1.secretsmanager"
echo "4. VPC: $VPC_ID"
echo "5. サブネット: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
echo "6. セキュリティグループ: $VPC_ENDPOINT_SG_ID"
echo "7. Private DNS名を有効にする: チェック"