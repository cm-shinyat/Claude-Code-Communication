#!/usr/bin/env zsh
# Project Forest 本格デモ環境 完全削除スクリプト

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
DOMAIN_NAME="demo.project-forest.com"
HOSTED_ZONE_ID="Z1234567890123"  # 変更が必要

echo "${RED}⚠️  Project Forest デモ環境の完全削除を開始します${NC}"
echo ""
echo "${YELLOW}この操作は以下のすべてのリソースを削除します：${NC}"
echo "- ECS クラスター・サービス"
echo "- Application Load Balancer"
echo "- RDS データベース（データ完全削除）"
echo "- VPC・サブネット・セキュリティグループ"
echo "- SSL証明書・Route 53レコード"
echo "- IAMロール・Secrets Manager"
echo "- ECR・CloudWatch Logs"
echo ""
echo "${RED}⚠️  この操作は不可逆的です。データは復旧できません。${NC}"
echo "${YELLOW}本当に削除しますか？ (DELETE と入力してください)${NC}"
read -r CONFIRM
if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "削除をキャンセルしました"
    exit 0
fi

# アカウントID取得
ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

echo ""
echo "${YELLOW}🔄 ステップ 1: ECSサービス・クラスター削除${NC}"

# ECSサービス削除
echo "ECSサービス削除中..."
aws-vault exec shinyat -- aws ecs update-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --desired-count 0 \
  --region $REGION 2>/dev/null || echo "サービスが見つかりません"

sleep 10

aws-vault exec shinyat -- aws ecs delete-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --force \
  --region $REGION 2>/dev/null || echo "サービスが見つかりません"

# ECSクラスター削除
echo "ECSクラスター削除中..."
aws-vault exec shinyat -- aws ecs delete-cluster \
  --cluster ${PROJECT_NAME}-cluster \
  --region $REGION 2>/dev/null || echo "クラスターが見つかりません"

echo "${GREEN}✅ ECS削除完了${NC}"

echo ""
echo "${YELLOW}⚖️  ステップ 2: Application Load Balancer削除${NC}"

# ALB ARNを取得
ALB_ARN=$(aws-vault exec shinyat -- aws elbv2 describe-load-balancers \
  --names ${PROJECT_NAME}-alb \
  --region $REGION \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text 2>/dev/null)

if [[ "$ALB_ARN" != "None" ]] && [[ -n "$ALB_ARN" ]]; then
  echo "ALB削除中..."
  
  # リスナー削除
  LISTENER_ARNS=$(aws-vault exec shinyat -- aws elbv2 describe-listeners \
    --load-balancer-arn $ALB_ARN \
    --region $REGION \
    --query "Listeners[].ListenerArn" \
    --output text 2>/dev/null)
  
  for LISTENER_ARN in $LISTENER_ARNS; do
    aws-vault exec shinyat -- aws elbv2 delete-listener \
      --listener-arn $LISTENER_ARN \
      --region $REGION 2>/dev/null || true
  done
  
  # ターゲットグループ削除
  TG_ARN=$(aws-vault exec shinyat -- aws elbv2 describe-target-groups \
    --names ${PROJECT_NAME}-tg \
    --region $REGION \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text 2>/dev/null)
  
  if [[ "$TG_ARN" != "None" ]] && [[ -n "$TG_ARN" ]]; then
    aws-vault exec shinyat -- aws elbv2 delete-target-group \
      --target-group-arn $TG_ARN \
      --region $REGION 2>/dev/null || true
  fi
  
  # ALB削除
  aws-vault exec shinyat -- aws elbv2 delete-load-balancer \
    --load-balancer-arn $ALB_ARN \
    --region $REGION 2>/dev/null || true
    
  echo "ALB削除完了待機中..."
  sleep 30
else
  echo "ALBが見つかりません"
fi

echo "${GREEN}✅ ALB削除完了${NC}"

echo ""
echo "${YELLOW}🗄️  ステップ 3: RDS削除${NC}"

# RDSインスタンス削除
echo "RDS削除中（最終スナップショット作成）..."
aws-vault exec shinyat -- aws rds delete-db-instance \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --final-db-snapshot-identifier ${PROJECT_NAME}-db-final-snapshot-$(date +%Y%m%d) \
  --region $REGION 2>/dev/null || echo "RDSが見つかりません"

echo "RDS削除完了を待機中（5-10分かかります）..."
aws-vault exec shinyat -- aws rds wait db-instance-deleted \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --region $REGION 2>/dev/null || true

# DBサブネットグループ削除
echo "DBサブネットグループ削除中..."
aws-vault exec shinyat -- aws rds delete-db-subnet-group \
  --db-subnet-group-name ${PROJECT_NAME}-db-subnet-group \
  --region $REGION 2>/dev/null || echo "DBサブネットグループが見つかりません"

echo "${GREEN}✅ RDS削除完了${NC}"

echo ""
echo "${YELLOW}🌐 ステップ 4: Route 53レコード削除${NC}"

# ALB DNS名を取得（削除前に保存していた場合）
ALB_DNS_FILE="${PROJECT_NAME}-deployment-info.txt"
ALB_DNS=""
if [[ -f "$ALB_DNS_FILE" ]]; then
  ALB_DNS=$(grep "ALB DNS:" "$ALB_DNS_FILE" | cut -d' ' -f3 2>/dev/null || true)
fi

if [[ -n "$ALB_DNS" ]] && [[ "$HOSTED_ZONE_ID" != "Z1234567890123" ]]; then
  echo "Route 53 Aレコード削除中..."
  aws-vault exec shinyat -- aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch "{
      \"Changes\": [{
        \"Action\": \"DELETE\",
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
    --region $REGION 2>/dev/null || echo "Route 53レコードが見つかりません"
else
  echo "Route 53レコード削除をスキップ（DNS情報が不足）"
fi

echo "${GREEN}✅ Route 53削除完了${NC}"

echo ""
echo "${YELLOW}🔒 ステップ 5: SSL証明書削除${NC}"

# 証明書ARNを取得
CERTIFICATE_ARN=$(aws-vault exec shinyat -- aws acm list-certificates \
  --region $REGION \
  --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" \
  --output text 2>/dev/null)

if [[ -n "$CERTIFICATE_ARN" ]] && [[ "$CERTIFICATE_ARN" != "None" ]]; then
  echo "SSL証明書削除中..."
  aws-vault exec shinyat -- aws acm delete-certificate \
    --certificate-arn $CERTIFICATE_ARN \
    --region $REGION 2>/dev/null || echo "証明書削除に失敗"
else
  echo "SSL証明書が見つかりません"
fi

echo "${GREEN}✅ SSL証明書削除完了${NC}"

echo ""
echo "${YELLOW}👤 ステップ 6: IAMロール・ポリシー削除${NC}"

# ポリシーのデタッチ
echo "IAMポリシーデタッチ中..."
aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ${PROJECT_NAME}-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ${PROJECT_NAME}-execution-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${PROJECT_NAME}-secrets-policy 2>/dev/null || true

# カスタムポリシー削除
echo "カスタムポリシー削除中..."
aws-vault exec shinyat -- aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${PROJECT_NAME}-secrets-policy 2>/dev/null || echo "ポリシーが見つかりません"

# ロール削除
echo "IAMロール削除中..."
aws-vault exec shinyat -- aws iam delete-role \
  --role-name ${PROJECT_NAME}-execution-role 2>/dev/null || echo "ロールが見つかりません"

echo "${GREEN}✅ IAM削除完了${NC}"

echo ""
echo "${YELLOW}🔐 ステップ 7: Secrets Manager削除${NC}"

# シークレット削除
SECRET_ARN=$(aws-vault exec shinyat -- aws secretsmanager describe-secret \
  --secret-id ${PROJECT_NAME}/database \
  --region $REGION \
  --query "ARN" \
  --output text 2>/dev/null)

if [[ -n "$SECRET_ARN" ]] && [[ "$SECRET_ARN" != "None" ]]; then
  echo "Secrets Manager削除中..."
  aws-vault exec shinyat -- aws secretsmanager delete-secret \
    --secret-id $SECRET_ARN \
    --force-delete-without-recovery \
    --region $REGION 2>/dev/null || echo "シークレット削除に失敗"
else
  echo "Secrets Managerが見つかりません"
fi

echo "${GREEN}✅ Secrets Manager削除完了${NC}"

echo ""
echo "${YELLOW}📦 ステップ 8: ECR削除${NC}"

# ECRリポジトリ削除
echo "ECRリポジトリ削除中..."
aws-vault exec shinyat -- aws ecr delete-repository \
  --repository-name project-forest \
  --force \
  --region $REGION 2>/dev/null || echo "ECRリポジトリが見つかりません"

echo "${GREEN}✅ ECR削除完了${NC}"

echo ""
echo "${YELLOW}📝 ステップ 9: CloudWatchログ削除${NC}"

# ロググループ削除
echo "CloudWatchロググループ削除中..."
aws-vault exec shinyat -- aws logs delete-log-group \
  --log-group-name /ecs/${PROJECT_NAME} \
  --region $REGION 2>/dev/null || echo "ロググループが見つかりません"

echo "${GREEN}✅ CloudWatch削除完了${NC}"

echo ""
echo "${YELLOW}🛡️  ステップ 10: セキュリティグループ削除${NC}"

# セキュリティグループID取得
ALB_SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PROJECT_NAME}-alb-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION 2>/dev/null)

ECS_SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PROJECT_NAME}-ecs-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION 2>/dev/null)

RDS_SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PROJECT_NAME}-rds-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION 2>/dev/null)

# セキュリティグループ削除
echo "セキュリティグループ削除中..."
for SG_ID in $ALB_SG_ID $ECS_SG_ID $RDS_SG_ID; do
  if [[ "$SG_ID" != "None" ]] && [[ -n "$SG_ID" ]]; then
    aws-vault exec shinyat -- aws ec2 delete-security-group \
      --group-id $SG_ID \
      --region $REGION 2>/dev/null || echo "セキュリティグループ $SG_ID の削除に失敗"
  fi
done

echo "${GREEN}✅ セキュリティグループ削除完了${NC}"

echo ""
echo "${YELLOW}🌐 ステップ 11: VPCリソース削除${NC}"

# VPC ID取得
VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION 2>/dev/null)

if [[ "$VPC_ID" != "None" ]] && [[ -n "$VPC_ID" ]]; then
  echo "VPCリソース削除中..."
  
  # サブネット削除
  SUBNET_IDS=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[].SubnetId" \
    --output text \
    --region $REGION 2>/dev/null)
  
  for SUBNET_ID in $SUBNET_IDS; do
    aws-vault exec shinyat -- aws ec2 delete-subnet \
      --subnet-id $SUBNET_ID \
      --region $REGION 2>/dev/null || echo "サブネット $SUBNET_ID の削除に失敗"
  done
  
  # ルートテーブル削除
  ROUTE_TABLE_IDS=$(aws-vault exec shinyat -- aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-public-rt" \
    --query "RouteTables[].RouteTableId" \
    --output text \
    --region $REGION 2>/dev/null)
  
  for RT_ID in $ROUTE_TABLE_IDS; do
    aws-vault exec shinyat -- aws ec2 delete-route-table \
      --route-table-id $RT_ID \
      --region $REGION 2>/dev/null || echo "ルートテーブル $RT_ID の削除に失敗"
  done
  
  # インターネットゲートウェイのデタッチ・削除
  IGW_ID=$(aws-vault exec shinyat -- aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[0].InternetGatewayId" \
    --output text \
    --region $REGION 2>/dev/null)
  
  if [[ "$IGW_ID" != "None" ]] && [[ -n "$IGW_ID" ]]; then
    aws-vault exec shinyat -- aws ec2 detach-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --vpc-id $VPC_ID \
      --region $REGION 2>/dev/null || echo "IGWデタッチに失敗"
    
    aws-vault exec shinyat -- aws ec2 delete-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --region $REGION 2>/dev/null || echo "IGW削除に失敗"
  fi
  
  # VPC削除
  aws-vault exec shinyat -- aws ec2 delete-vpc \
    --vpc-id $VPC_ID \
    --region $REGION 2>/dev/null || echo "VPC削除に失敗"
else
  echo "VPCが見つかりません"
fi

echo "${GREEN}✅ VPC削除完了${NC}"

echo ""
echo "${BLUE}🎉 デモ環境削除完了！${NC}"
echo ""
echo "=== 削除されたリソース ==="
echo "✅ ECS クラスター・サービス"
echo "✅ Application Load Balancer"
echo "✅ RDS データベース"
echo "✅ VPC・サブネット・セキュリティグループ"
echo "✅ SSL証明書・Route 53レコード"
echo "✅ IAMロール・Secrets Manager"
echo "✅ ECR・CloudWatch Logs"
echo ""
echo "${YELLOW}⚠️  残る可能性があるリソース：${NC}"
echo "- RDSスナップショット（手動削除が必要）"
echo "- Route 53 ホストゾーン（ドメイン料金継続）"
echo "- 他のCloudWatchメトリクス"
echo ""
echo "${YELLOW}💰 請求額の確認：${NC}"
echo "- 翌日以降にAWS請求ダッシュボードで料金を確認してください"
echo "- 予期しない料金が発生している場合は、残りリソースを確認してください"
echo ""
echo "${GREEN}✅ クリーンアップ完了しました！${NC}"

# 設定情報ファイルも削除
if [[ -f "${PROJECT_NAME}-deployment-info.txt" ]]; then
  rm "${PROJECT_NAME}-deployment-info.txt"
  echo "設定情報ファイルも削除しました"
fi