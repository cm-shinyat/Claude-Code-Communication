#!/usr/bin/env zsh
# ECSサービス再起動スクリプト
# VPCエンドポイント設定後にプライベートサブネットでサービスを再起動

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

echo "${BLUE}🔄 ECSサービス再起動を開始します${NC}"
echo ""

# 必要な情報を取得
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
echo "Private Subnet 1: $PRIVATE_SUBNET_1"
echo "Private Subnet 2: $PRIVATE_SUBNET_2"
echo "ECS Security Group: $ECS_SG_ID"

# 1. 現在のサービスを削除
echo ""
echo "${YELLOW}🛑 ステップ 1: 現在のサービス削除${NC}"

# サービスが存在するか確認
SERVICE_EXISTS=$(aws-vault exec shinyat -- aws ecs describe-services \
  --cluster ${PROJECT_NAME}-cluster \
  --services ${PROJECT_NAME}-service \
  --region $REGION \
  --query "length(services[?status=='ACTIVE'])" \
  --output text 2>/dev/null || echo "0")

if [[ "$SERVICE_EXISTS" -gt 0 ]]; then
  echo "既存のサービスを停止中..."
  aws-vault exec shinyat -- aws ecs update-service \
    --cluster ${PROJECT_NAME}-cluster \
    --service ${PROJECT_NAME}-service \
    --desired-count 0 \
    --region $REGION

  echo "サービス停止を待機中..."
  sleep 30

  echo "サービス削除中..."
  aws-vault exec shinyat -- aws ecs delete-service \
    --cluster ${PROJECT_NAME}-cluster \
    --service ${PROJECT_NAME}-service \
    --force \
    --region $REGION

  echo "${GREEN}✅ サービス削除完了${NC}"
else
  echo "既存のサービスが見つかりません"
fi

# 2. 新しいサービスを作成（プライベートサブネット使用）
echo ""
echo "${YELLOW}🚀 ステップ 2: 新しいサービス作成（プライベートサブネット + VPCエンドポイント）${NC}"
aws-vault exec shinyat -- aws ecs create-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name ${PROJECT_NAME}-service \
  --task-definition ${PROJECT_NAME}-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={
    subnets=[\"$PRIVATE_SUBNET_1\",\"$PRIVATE_SUBNET_2\"],
    securityGroups=[\"$ECS_SG_ID\"],
    assignPublicIp=DISABLED
  }" \
  --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=project-forest,containerPort=3000" \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=50" \
  --region $REGION

echo "${GREEN}✅ 新しいサービス作成完了${NC}"

# 3. サービス起動確認
echo ""
echo "${YELLOW}⏳ ステップ 3: サービス起動確認${NC}"
echo "サービス起動を待機中（約3分）..."
sleep 180

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
  --query "taskArns" \
  --output text)

if [[ -n "$TASK_ARNS" ]] && [[ "$TASK_ARNS" != "None" ]]; then
  echo ""
  echo "実行中のタスク数: $(echo $TASK_ARNS | wc -w)"
  
  # 最初のタスクの詳細確認
  FIRST_TASK=$(echo $TASK_ARNS | cut -d' ' -f1)
  if [[ -n "$FIRST_TASK" ]]; then
    echo "タスクARN: $FIRST_TASK"
    
    TASK_STATUS=$(aws-vault exec shinyat -- aws ecs describe-tasks \
      --cluster ${PROJECT_NAME}-cluster \
      --tasks $FIRST_TASK \
      --region $REGION \
      --query "tasks[0].{LastStatus:lastStatus,HealthStatus:healthStatus}" \
      --output table 2>/dev/null)
    
    echo "タスク状態:"
    echo "$TASK_STATUS"
  fi
else
  echo "${RED}❌ 実行中のタスクがありません${NC}"
  echo ""
  echo "問題の確認:"
  echo "1. ログ確認: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"
  echo "2. タスク状態詳細: aws-vault exec shinyat -- aws ecs describe-services --cluster ${PROJECT_NAME}-cluster --services ${PROJECT_NAME}-service --region $REGION"
fi

# 4. ターゲットグループの健康状態確認
echo ""
echo "${YELLOW}🎯 ステップ 4: ターゲットグループ健康状態確認${NC}"
echo "ヘルスチェック完了を待機中..."
sleep 60

HEALTH_STATUS=$(aws-vault exec shinyat -- aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region $REGION \
  --output table 2>/dev/null)

echo "ターゲット健康状態:"
echo "$HEALTH_STATUS"

# 5. 最新ログ表示
echo ""
echo "${YELLOW}📝 ステップ 5: 最新ログ確認${NC}"
echo "最新のログ（最大10行）:"
aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} \
  --since 5m \
  --region $REGION 2>/dev/null | tail -10 || echo "ログが見つかりません"

echo ""
echo "${GREEN}🎉 ECSサービス再起動完了${NC}"
echo ""
echo "=== 確認事項 ==="
echo "1. サービスが正常に起動していることを確認"
echo "2. タスクでSecrets Managerエラーが発生していないことを確認"
echo "3. ターゲットが 'healthy' 状態になることを確認"
echo "4. https://demo1.cc.cm-ga.me でアクセス確認"
echo ""
echo "=== 追加確認コマンド ==="
echo "ログ監視: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"
echo "診断実行: ./diagnose-demo.sh"
echo "VPCエンドポイント確認: aws-vault exec shinyat -- aws ec2 describe-vpc-endpoints --region $REGION"