#!/usr/bin/env zsh
# VPC DNS設定修正 + VPCエンドポイント作成スクリプト

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
VPC_ID="vpc-0eb889d242976f7c2"
PRIVATE_SUBNET_1="subnet-045327644d0d5e5df"
PRIVATE_SUBNET_2="subnet-068d374080c7f3de6"
VPC_ENDPOINT_SG_ID="sg-0503d4febe9942e05"

echo "${BLUE}🔧 VPC DNS設定修正 + VPCエンドポイント作成${NC}"
echo ""

# 1. 現在のVPC DNS設定確認
echo "${YELLOW}📋 ステップ 1: 現在のVPC DNS設定確認${NC}"

DNS_SUPPORT=$(aws-vault exec shinyat -- aws ec2 describe-vpc-attribute \
  --vpc-id $VPC_ID \
  --attribute enableDnsSupport \
  --region $REGION \
  --query "EnableDnsSupport.Value" \
  --output text)

DNS_HOSTNAMES=$(aws-vault exec shinyat -- aws ec2 describe-vpc-attribute \
  --vpc-id $VPC_ID \
  --attribute enableDnsHostnames \
  --region $REGION \
  --query "EnableDnsHostnames.Value" \
  --output text)

echo "DNS Support: $DNS_SUPPORT"
echo "DNS Hostnames: $DNS_HOSTNAMES"

# 2. DNS設定を有効化
echo ""
echo "${YELLOW}🔧 ステップ 2: DNS設定を有効化${NC}"

if [[ "$DNS_SUPPORT" != "True" ]]; then
  echo "DNS Support を有効化中..."
  aws-vault exec shinyat -- aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-support \
    --region $REGION
  echo "${GREEN}✅ DNS Support 有効化完了${NC}"
else
  echo "DNS Support は既に有効です"
fi

if [[ "$DNS_HOSTNAMES" != "True" ]]; then
  echo "DNS Hostnames を有効化中..."
  aws-vault exec shinyat -- aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames \
    --region $REGION
  echo "${GREEN}✅ DNS Hostnames 有効化完了${NC}"
else
  echo "DNS Hostnames は既に有効です"
fi

# 3. 設定確認
echo ""
echo "${YELLOW}✅ ステップ 3: 修正後の設定確認${NC}"

DNS_SUPPORT_AFTER=$(aws-vault exec shinyat -- aws ec2 describe-vpc-attribute \
  --vpc-id $VPC_ID \
  --attribute enableDnsSupport \
  --region $REGION \
  --query "EnableDnsSupport.Value" \
  --output text)

DNS_HOSTNAMES_AFTER=$(aws-vault exec shinyat -- aws ec2 describe-vpc-attribute \
  --vpc-id $VPC_ID \
  --attribute enableDnsHostnames \
  --region $REGION \
  --query "EnableDnsHostnames.Value" \
  --output text)

echo "修正後 DNS Support: $DNS_SUPPORT_AFTER"
echo "修正後 DNS Hostnames: $DNS_HOSTNAMES_AFTER"

if [[ "$DNS_SUPPORT_AFTER" == "True" ]] && [[ "$DNS_HOSTNAMES_AFTER" == "True" ]]; then
  echo "${GREEN}✅ DNS設定修正完了${NC}"
else
  echo "${RED}❌ DNS設定修正失敗${NC}"
  exit 1
fi

# 4. VPCエンドポイント作成
echo ""
echo "${YELLOW}🔐 ステップ 4: Secrets Manager VPCエンドポイント作成${NC}"

SECRETS_ENDPOINT=$(aws-vault exec shinyat -- aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.${REGION}.secretsmanager \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --security-group-ids $VPC_ENDPOINT_SG_ID \
  --private-dns-enabled \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT_NAME}-secrets-manager-endpoint}]" \
  --region $REGION \
  --query "VpcEndpoint.VpcEndpointId" \
  --output text)

if [[ $? -eq 0 ]] && [[ "$SECRETS_ENDPOINT" != "None" ]]; then
  echo "${GREEN}✅ Secrets Manager VPCエンドポイント作成成功: $SECRETS_ENDPOINT${NC}"
else
  echo "${RED}❌ Secrets Manager VPCエンドポイント作成失敗${NC}"
  exit 1
fi

# 5. ECR DKR VPCエンドポイント作成
echo ""
echo "${YELLOW}📦 ステップ 5: ECR DKR VPCエンドポイント作成${NC}"

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
  --output text)

if [[ $? -eq 0 ]] && [[ "$ECR_DKR_ENDPOINT" != "None" ]]; then
  echo "${GREEN}✅ ECR DKR VPCエンドポイント作成成功: $ECR_DKR_ENDPOINT${NC}"
else
  echo "${YELLOW}⚠️  ECR DKR VPCエンドポイント作成失敗（続行）${NC}"
  ECR_DKR_ENDPOINT="None"
fi

# 6. ECR API VPCエンドポイント作成
echo ""
echo "${YELLOW}📦 ステップ 6: ECR API VPCエンドポイント作成${NC}"

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
  --output text)

if [[ $? -eq 0 ]] && [[ "$ECR_API_ENDPOINT" != "None" ]]; then
  echo "${GREEN}✅ ECR API VPCエンドポイント作成成功: $ECR_API_ENDPOINT${NC}"
else
  echo "${YELLOW}⚠️  ECR API VPCエンドポイント作成失敗（続行）${NC}"
  ECR_API_ENDPOINT="None"
fi

# 7. CloudWatch Logs VPCエンドポイント作成
echo ""
echo "${YELLOW}📝 ステップ 7: CloudWatch Logs VPCエンドポイント作成${NC}"

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
  --output text)

if [[ $? -eq 0 ]] && [[ "$LOGS_ENDPOINT" != "None" ]]; then
  echo "${GREEN}✅ CloudWatch Logs VPCエンドポイント作成成功: $LOGS_ENDPOINT${NC}"
else
  echo "${YELLOW}⚠️  CloudWatch Logs VPCエンドポイント作成失敗（続行）${NC}"
  LOGS_ENDPOINT="None"
fi

# 8. VPCエンドポイント状態確認
echo ""
echo "${YELLOW}⏳ ステップ 8: VPCエンドポイント状態確認${NC}"
echo "VPCエンドポイントの準備完了を待機中..."
sleep 60

echo ""
echo "=== 作成されたVPCエンドポイント ==="
echo "• Secrets Manager: $SECRETS_ENDPOINT"
echo "• ECR DKR: $ECR_DKR_ENDPOINT"
echo "• ECR API: $ECR_API_ENDPOINT"
echo "• CloudWatch Logs: $LOGS_ENDPOINT"
echo "• S3 Gateway: vpce-03d39905cc6c4a7a3 (既存)"

# VPCエンドポイント一覧表示
echo ""
echo "VPCエンドポイント詳細:"
aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region $REGION \
  --query "VpcEndpoints[].{ID:VpcEndpointId,Service:ServiceName,State:State}" \
  --output table

echo ""
echo "${GREEN}🎉 VPC設定修正 + VPCエンドポイント作成完了${NC}"
echo ""
echo "${YELLOW}💡 次のステップ: ECSサービスを再起動してください${NC}"
echo "./wait-and-restart-ecs.sh"