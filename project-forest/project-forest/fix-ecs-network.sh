#!/usr/bin/env zsh
# ECSサービスのネットワーク設定修正スクリプト
# プライベート → パブリックサブネットに変更してSecrets Manager接続問題を解決

set -e

# 色の定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 設定変数
REGION="ap-northeast-1"
PROJECT_NAME="project-forest-demo"

echo "${YELLOW}🔧 ECSサービスのネットワーク設定修正を開始します${NC}"
echo ""

# 1. 現在のサービスを停止・削除
echo "${YELLOW}🛑 ステップ 1: 現在のサービス削除${NC}"
aws-vault exec shinyat -- aws ecs update-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --desired-count 0 \
  --region $REGION

echo "サービス停止を待機中..."
sleep 30

aws-vault exec shinyat -- aws ecs delete-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --force \
  --region $REGION

echo "${GREEN}✅ サービス削除完了${NC}"

# 2. 必要な情報を取得
echo ""
echo "${YELLOW}📋 ステップ 2: ネットワーク情報取得${NC}"

VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION)

PUBLIC_SUBNET_1=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-public-1a" \
  --query "Subnets[0].SubnetId" \
  --output text \
  --region $REGION)

PUBLIC_SUBNET_2=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-public-1c" \
  --query "Subnets[0].SubnetId" \
  --output text \
  --region $REGION)

ECS_SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PROJECT_NAME}-ecs-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION)

TARGET_GROUP_ARN=$(aws-vault exec shinyat -- aws elbv2 describe-target-groups \
  --names ${PROJECT_NAME}-tg \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text \
  --region $REGION)

echo "VPC ID: $VPC_ID"
echo "Public Subnet 1: $PUBLIC_SUBNET_1"
echo "Public Subnet 2: $PUBLIC_SUBNET_2"
echo "ECS Security Group: $ECS_SG_ID"
echo "Target Group ARN: $TARGET_GROUP_ARN"

# 3. 新しいサービスを作成（パブリックサブネット使用）
echo ""
echo "${YELLOW}🚀 ステップ 3: 新しいサービス作成（パブリックサブネット）${NC}"
aws-vault exec shinyat -- aws ecs create-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name ${PROJECT_NAME}-service \
  --task-definition ${PROJECT_NAME}-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={
    subnets=[\"$PUBLIC_SUBNET_1\",\"$PUBLIC_SUBNET_2\"],
    securityGroups=[\"$ECS_SG_ID\"],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=project-forest,containerPort=3000" \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=50" \
  --region $REGION

echo "${GREEN}✅ 新しいサービス作成完了${NC}"

# 4. サービス起動確認
echo ""
echo "${YELLOW}⏳ ステップ 4: サービス起動確認${NC}"
echo "サービス起動を待機中（約2分）..."
sleep 120

# サービス状態確認
SERVICE_STATUS=$(aws-vault exec shinyat -- aws ecs describe-services \
  --cluster ${PROJECT_NAME}-cluster \
  --services ${PROJECT_NAME}-service \
  --region $REGION \
  --query "services[0].{DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}" \
  --output table)

echo "サービス状態:"
echo "$SERVICE_STATUS"

# タスク状態確認
TASK_ARNS=$(aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name ${PROJECT_NAME}-service \
  --region $REGION \
  --query "taskArns[0]" \
  --output text)

if [[ -n "$TASK_ARNS" ]] && [[ "$TASK_ARNS" != "None" ]]; then
  echo ""
  echo "タスク状態確認中..."
  TASK_STATUS=$(aws-vault exec shinyat -- aws ecs describe-tasks \
    --cluster ${PROJECT_NAME}-cluster \
    --tasks $TASK_ARNS \
    --region $REGION \
    --query "tasks[0].{LastStatus:lastStatus,HealthStatus:healthStatus}" \
    --output table)
  
  echo "$TASK_STATUS"
fi

# 5. ターゲットグループの健康状態確認
echo ""
echo "${YELLOW}🎯 ステップ 5: ターゲットグループ健康状態確認${NC}"
sleep 30  # ヘルスチェック完了を待機

HEALTH_STATUS=$(aws-vault exec shinyat -- aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region $REGION \
  --output table)

echo "ターゲット健康状態:"
echo "$HEALTH_STATUS"

echo ""
echo "${GREEN}🎉 修正完了！${NC}"
echo ""
echo "=== 確認事項 ==="
echo "1. サービスが正常に起動していることを確認"
echo "2. ターゲットが 'healthy' 状態になることを確認"
echo "3. https://demo1.cc.cm-ga.me でアクセス確認"
echo ""
echo "=== 追加確認コマンド ==="
echo "ログ確認: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"
echo "診断実行: ./diagnose-demo.sh"