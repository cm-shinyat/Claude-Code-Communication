#!/usr/bin/env zsh
# ECR VPCエンドポイント設定検査スクリプト

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
ECR_DKR_ENDPOINT="vpce-07bbb6822cab90739"
ECR_API_ENDPOINT="vpce-0f6d3b87a398c9cdf"
S3_ENDPOINT="vpce-03d39905cc6c4a7a3"
VPC_ENDPOINT_SG_ID="sg-0503d4febe9942e05"
ECS_SG_ID="sg-00cabac718b3d77b0"

echo "${BLUE}🔍 ECR VPCエンドポイント設定検査開始${NC}"
echo ""
echo "=== 検査対象 ==="
echo "VPC: $VPC_ID"
echo "Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
echo "ECR DKR Endpoint: $ECR_DKR_ENDPOINT"
echo "ECR API Endpoint: $ECR_API_ENDPOINT"
echo "S3 Gateway Endpoint: $S3_ENDPOINT"
echo ""

# 検査結果カウンター
PASS_COUNT=0
FAIL_COUNT=0

function check_result() {
    local test_name="$1"
    local result="$2"
    local expected="$3"
    
    if [[ "$result" == "$expected" ]]; then
        echo "${GREEN}✅ PASS${NC}: $test_name"
        ((PASS_COUNT++))
    else
        echo "${RED}❌ FAIL${NC}: $test_name"
        echo "   Expected: $expected"
        echo "   Actual: $result"
        ((FAIL_COUNT++))
    fi
}

function check_contains() {
    local test_name="$1"
    local result="$2"
    local expected="$3"
    
    if echo "$result" | grep -q "$expected"; then
        echo "${GREEN}✅ PASS${NC}: $test_name"
        ((PASS_COUNT++))
    else
        echo "${RED}❌ FAIL${NC}: $test_name"
        echo "   Expected to contain: $expected"
        echo "   Actual: $result"
        ((FAIL_COUNT++))
    fi
}

echo "${YELLOW}📋 検査 1: ECR DKR VPCエンドポイント詳細${NC}"

# ECR DKR エンドポイントの状態確認
ECR_DKR_STATE=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_DKR_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].State" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECR DKR エンドポイント状態" "$ECR_DKR_STATE" "available"

# プライベートDNS有効化確認
ECR_DKR_DNS=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_DKR_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].PrivateDnsEnabled" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECR DKR プライベートDNS有効" "$ECR_DKR_DNS" "True"

# サブネット配置確認
ECR_DKR_SUBNETS=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_DKR_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].SubnetIds" \
  --output text 2>/dev/null || echo "ERROR")

check_contains "ECR DKR サブネット1配置" "$ECR_DKR_SUBNETS" "$PRIVATE_SUBNET_1"
check_contains "ECR DKR サブネット2配置" "$ECR_DKR_SUBNETS" "$PRIVATE_SUBNET_2"

echo ""
echo "${YELLOW}📋 検査 2: ECR API VPCエンドポイント詳細${NC}"

# ECR API エンドポイントの状態確認
ECR_API_STATE=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_API_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].State" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECR API エンドポイント状態" "$ECR_API_STATE" "available"

# プライベートDNS有効化確認
ECR_API_DNS=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_API_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].PrivateDnsEnabled" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECR API プライベートDNS有効" "$ECR_API_DNS" "True"

# サブネット配置確認
ECR_API_SUBNETS=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_API_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].SubnetIds" \
  --output text 2>/dev/null || echo "ERROR")

check_contains "ECR API サブネット1配置" "$ECR_API_SUBNETS" "$PRIVATE_SUBNET_1"
check_contains "ECR API サブネット2配置" "$ECR_API_SUBNETS" "$PRIVATE_SUBNET_2"

echo ""
echo "${YELLOW}📋 検査 3: S3 Gateway エンドポイント設定${NC}"

# S3 エンドポイントの状態確認
S3_STATE=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $S3_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].State" \
  --output text 2>/dev/null || echo "ERROR")

check_result "S3 Gateway エンドポイント状態" "$S3_STATE" "available"

# プライベートサブネットのルートテーブル取得
ROUTE_TABLE_1=$(aws-vault exec shinyat -- aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_1" \
  --region $REGION \
  --query "RouteTables[0].RouteTableId" \
  --output text 2>/dev/null || echo "ERROR")

ROUTE_TABLE_2=$(aws-vault exec shinyat -- aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_2" \
  --region $REGION \
  --query "RouteTables[0].RouteTableId" \
  --output text 2>/dev/null || echo "ERROR")

echo "   Route Table 1: $ROUTE_TABLE_1"
echo "   Route Table 2: $ROUTE_TABLE_2"

# S3エンドポイントのルートテーブル関連付け確認
S3_ROUTE_TABLES=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $S3_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].RouteTableIds" \
  --output text 2>/dev/null || echo "ERROR")

check_contains "S3エンドポイント ルートテーブル1関連付け" "$S3_ROUTE_TABLES" "$ROUTE_TABLE_1"
check_contains "S3エンドポイント ルートテーブル2関連付け" "$S3_ROUTE_TABLES" "$ROUTE_TABLE_2"

echo ""
echo "${YELLOW}📋 検査 4: VPCエンドポイント用セキュリティグループ${NC}"

# VPCエンドポイントSGのインバウンドルール確認
VPC_SG_INBOUND=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $VPC_ENDPOINT_SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`443\` && ToPort==\`443\`].IpRanges[0].CidrIp" \
  --output text 2>/dev/null || echo "ERROR")

check_result "VPCエンドポイントSG HTTPS許可" "$VPC_SG_INBOUND" "10.0.0.0/16"

# ECR DKRエンドポイントのセキュリティグループ確認
ECR_DKR_SG=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_DKR_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].Groups[0].GroupId" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECR DKR エンドポイントSG設定" "$ECR_DKR_SG" "$VPC_ENDPOINT_SG_ID"

# ECR APIエンドポイントのセキュリティグループ確認
ECR_API_SG=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_API_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].Groups[0].GroupId" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECR API エンドポイントSG設定" "$ECR_API_SG" "$VPC_ENDPOINT_SG_ID"

echo ""
echo "${YELLOW}📋 検査 5: ECSセキュリティグループのアウトバウンドルール${NC}"

# ECS SGのアウトバウンドルール確認（全許可）
ECS_SG_ALL_OUTBOUND=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $ECS_SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissionsEgress[?IpProtocol==\`-1\`].IpRanges[0].CidrIp" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECS SG 全アウトバウンド許可" "$ECS_SG_ALL_OUTBOUND" "0.0.0.0/0"

# ECS SGのVPCエンドポイントへのHTTPSアウトバウンド確認
ECS_SG_VPC_OUTBOUND=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $ECS_SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissionsEgress[?FromPort==\`443\` && ToPort==\`443\`].UserIdGroupPairs[0].GroupId" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECS SG VPCエンドポイントHTTPS許可" "$ECS_SG_VPC_OUTBOUND" "$VPC_ENDPOINT_SG_ID"

echo ""
echo "${YELLOW}📋 検査 6: ネットワークインターフェース詳細${NC}"

# ECR DKR エンドポイントのENI詳細
ECR_DKR_ENI=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_DKR_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].NetworkInterfaceIds[0]" \
  --output text 2>/dev/null || echo "ERROR")

if [[ "$ECR_DKR_ENI" != "ERROR" ]] && [[ -n "$ECR_DKR_ENI" ]]; then
    ECR_DKR_IP=$(aws-vault exec shinyat -- aws ec2 describe-network-interfaces \
      --network-interface-ids $ECR_DKR_ENI \
      --region $REGION \
      --query "NetworkInterfaces[0].PrivateIpAddress" \
      --output text 2>/dev/null || echo "ERROR")
    
    ECR_DKR_STATUS=$(aws-vault exec shinyat -- aws ec2 describe-network-interfaces \
      --network-interface-ids $ECR_DKR_ENI \
      --region $REGION \
      --query "NetworkInterfaces[0].Status" \
      --output text 2>/dev/null || echo "ERROR")
    
    echo "   ECR DKR ENI: $ECR_DKR_ENI"
    echo "   Private IP: $ECR_DKR_IP"
    check_result "ECR DKR ENI 状態" "$ECR_DKR_STATUS" "in-use"
fi

# ECR API エンドポイントのENI詳細
ECR_API_ENI=$(aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids $ECR_API_ENDPOINT \
  --region $REGION \
  --query "VpcEndpoints[0].NetworkInterfaceIds[0]" \
  --output text 2>/dev/null || echo "ERROR")

if [[ "$ECR_API_ENI" != "ERROR" ]] && [[ -n "$ECR_API_ENI" ]]; then
    ECR_API_IP=$(aws-vault exec shinyat -- aws ec2 describe-network-interfaces \
      --network-interface-ids $ECR_API_ENI \
      --region $REGION \
      --query "NetworkInterfaces[0].PrivateIpAddress" \
      --output text 2>/dev/null || echo "ERROR")
    
    ECR_API_STATUS=$(aws-vault exec shinyat -- aws ec2 describe-network-interfaces \
      --network-interface-ids $ECR_API_ENI \
      --region $REGION \
      --query "NetworkInterfaces[0].Status" \
      --output text 2>/dev/null || echo "ERROR")
    
    echo "   ECR API ENI: $ECR_API_ENI"
    echo "   Private IP: $ECR_API_IP"
    check_result "ECR API ENI 状態" "$ECR_API_STATUS" "in-use"
fi

echo ""
echo "${YELLOW}📋 検査 7: DNS解決テスト${NC}"

# VPC DNS設定確認
VPC_DNS_SUPPORT=$(aws-vault exec shinyat -- aws ec2 describe-vpc-attribute \
  --vpc-id $VPC_ID \
  --attribute enableDnsSupport \
  --region $REGION \
  --query "EnableDnsSupport.Value" \
  --output text 2>/dev/null || echo "ERROR")

VPC_DNS_HOSTNAMES=$(aws-vault exec shinyat -- aws ec2 describe-vpc-attribute \
  --vpc-id $VPC_ID \
  --attribute enableDnsHostnames \
  --region $REGION \
  --query "EnableDnsHostnames.Value" \
  --output text 2>/dev/null || echo "ERROR")

check_result "VPC DNS Support" "$VPC_DNS_SUPPORT" "True"
check_result "VPC DNS Hostnames" "$VPC_DNS_HOSTNAMES" "True"

echo ""
echo "${YELLOW}📋 検査 8: ECRイメージ存在確認${NC}"

# ECRリポジトリの存在確認
ECR_REPO_EXISTS=$(aws-vault exec shinyat -- aws ecr describe-repositories \
  --repository-names project-forest \
  --region $REGION \
  --query "repositories[0].repositoryName" \
  --output text 2>/dev/null || echo "ERROR")

check_result "ECRリポジトリ存在" "$ECR_REPO_EXISTS" "project-forest"

# latest タグのイメージ存在確認
if [[ "$ECR_REPO_EXISTS" == "project-forest" ]]; then
    ECR_IMAGE_EXISTS=$(aws-vault exec shinyat -- aws ecr describe-images \
      --repository-name project-forest \
      --image-ids imageTag=latest \
      --region $REGION \
      --query "imageDetails[0].imageId.imageTag" \
      --output text 2>/dev/null || echo "ERROR")
    
    check_result "ECR latest イメージ存在" "$ECR_IMAGE_EXISTS" "latest"
else
    echo "${RED}❌ FAIL${NC}: ECR latest イメージ存在確認 (リポジトリが存在しません)"
    ((FAIL_COUNT++))
fi

echo ""
echo "${BLUE}📊 検査結果サマリー${NC}"
echo "==============================="
echo "${GREEN}✅ PASS: $PASS_COUNT 項目${NC}"
echo "${RED}❌ FAIL: $FAIL_COUNT 項目${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo "${GREEN}🎉 すべての検査に合格しました！${NC}"
    echo "ECR VPCエンドポイント設定は正常です。"
    echo ""
    echo "問題が解決しない場合は、以下を確認してください："
    echo "1. IAM実行ロールのECR権限"
    echo "2. タスク定義の設定"
    echo "3. ECSサービスの再デプロイ"
else
    echo "${RED}⚠️  $FAIL_COUNT 項目で問題が見つかりました${NC}"
    echo ""
    echo "修正が必要な項目を確認して、適切な設定に変更してください。"
    echo "修正後、ECSサービスを再デプロイしてください："
    echo "aws-vault exec shinyat -- aws ecs update-service --cluster ${PROJECT_NAME}-cluster --service ${PROJECT_NAME}-service --force-new-deployment --region $REGION"
fi

echo ""
echo "${YELLOW}💡 追加確認コマンド${NC}"
echo "ログ確認: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"
echo "タスク状態: aws-vault exec shinyat -- aws ecs describe-services --cluster ${PROJECT_NAME}-cluster --services ${PROJECT_NAME}-service --region $REGION"