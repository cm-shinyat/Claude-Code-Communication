#!/usr/bin/env zsh
# ECSサービス強制再起動スクリプト

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

echo "${BLUE}🔧 ECSサービス強制再起動${NC}"
echo ""

# 1. 現在の状況確認
echo "${YELLOW}📋 ステップ 1: 現在の状況確認${NC}"

SERVICE_STATUS=$(aws-vault exec shinyat -- aws ecs describe-services \
  --cluster ${PROJECT_NAME}-cluster \
  --services ${PROJECT_NAME}-service \
  --region $REGION \
  --query "services[0].{Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}" \
  --output table 2>/dev/null || echo "サービスが見つかりません")

echo "現在のサービス状態:"
echo "$SERVICE_STATUS"

# 2. サービスの強制停止
echo ""
echo "${YELLOW}🛑 ステップ 2: サービス強制停止${NC}"

aws-vault exec shinyat -- aws ecs update-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --desired-count 0 \
  --force-new-deployment \
  --region $REGION 2>/dev/null || echo "サービス更新失敗またはサービスが存在しません"

echo "強制停止実行完了 - 60秒待機中..."
sleep 60

# 3. タスクの強制停止
echo ""
echo "${YELLOW}📦 ステップ 3: タスク強制停止${NC}"

TASK_ARNS=$(aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster ${PROJECT_NAME}-cluster \
  --region $REGION \
  --query "taskArns" \
  --output text 2>/dev/null || echo "")

if [[ -n "$TASK_ARNS" ]] && [[ "$TASK_ARNS" != "None" ]]; then
  echo "実行中のタスクを強制停止中..."
  for TASK_ARN in $TASK_ARNS; do
    echo "タスク停止: $TASK_ARN"
    aws-vault exec shinyat -- aws ecs stop-task \
      --cluster ${PROJECT_NAME}-cluster \
      --task $TASK_ARN \
      --region $REGION 2>/dev/null || echo "タスク停止失敗: $TASK_ARN"
  done
  
  echo "タスク停止完了を待機中..."
  sleep 30
else
  echo "実行中のタスクはありません"
fi

# 4. サービス削除
echo ""
echo "${YELLOW}🗑️  ステップ 4: サービス削除${NC}"

aws-vault exec shinyat -- aws ecs delete-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --force \
  --region $REGION 2>/dev/null || echo "サービス削除失敗またはサービスが存在しません"

echo "サービス削除を待機中..."
sleep 30

# 5. 削除確認
DELETE_STATUS=$(aws-vault exec shinyat -- aws ecs describe-services \
  --cluster ${PROJECT_NAME}-cluster \
  --services ${PROJECT_NAME}-service \
  --region $REGION \
  --query "services[0].status" \
  --output text 2>/dev/null || echo "MISSING")

echo "削除後のサービス状態: $DELETE_STATUS"

# 6. 新しいサービス作成
echo ""
echo "${YELLOW}🚀 ステップ 5: 新しいサービス作成${NC}"

TARGET_GROUP_ARN=$(aws-vault exec shinyat -- aws elbv2 describe-target-groups \
  --names ${PROJECT_NAME}-tg \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text \
  --region $REGION)

echo "Target Group ARN: $TARGET_GROUP_ARN"

SERVICE_NAME="${PROJECT_NAME}-service"
if [[ "$DELETE_STATUS" != "MISSING" ]] && [[ "$DELETE_STATUS" != "None" ]]; then
  # 削除が完了していない場合は新しい名前を使用
  SERVICE_NAME="${PROJECT_NAME}-service-v2"
  echo "${YELLOW}⚠️  元のサービスがまだ存在するため、新しい名前を使用: $SERVICE_NAME${NC}"
fi

aws-vault exec shinyat -- aws ecs create-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name $SERVICE_NAME \
  --task-definition ${PROJECT_NAME}-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={
    subnets=[\"subnet-045327644d0d5e5df\",\"subnet-068d374080c7f3de6\"],
    securityGroups=[\"sg-00cabac718b3d77b0\"],
    assignPublicIp=DISABLED
  }" \
  --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=project-forest,containerPort=3000" \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=50" \
  --region $REGION

if [[ $? -eq 0 ]]; then
  echo "${GREEN}✅ サービス作成成功: $SERVICE_NAME${NC}"
else
  echo "${RED}❌ サービス作成失敗${NC}"
  exit 1
fi

# 7. サービス起動確認
echo ""
echo "${YELLOW}⏳ ステップ 6: サービス起動確認${NC}"
echo "サービス起動を待機中（約3分）..."
sleep 180

# サービス状態確認
NEW_SERVICE_STATUS=$(aws-vault exec shinyat -- aws ecs describe-services \
  --cluster ${PROJECT_NAME}-cluster \
  --services $SERVICE_NAME \
  --region $REGION \
  --query "services[0].{DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}" \
  --output table)

echo "新しいサービス状態:"
echo "$NEW_SERVICE_STATUS"

# 8. タスク詳細確認
TASK_ARNS=$(aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name $SERVICE_NAME \
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
  echo "2. タスク詳細: aws-vault exec shinyat -- aws ecs describe-services --cluster ${PROJECT_NAME}-cluster --services $SERVICE_NAME --region $REGION"
fi

# 9. 最新ログ確認
echo ""
echo "${YELLOW}📝 ステップ 7: 最新ログ確認${NC}"
echo "最新のログ（最大10行）:"
aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} \
  --since 3m \
  --region $REGION 2>/dev/null | tail -10 || echo "ログが見つかりません"

echo ""
echo "${GREEN}🎉 強制再起動完了${NC}"
echo ""
echo "=== 確認事項 ==="
echo "1. 新しいサービス: $SERVICE_NAME"
echo "2. VPCエンドポイント経由でSecrets Managerにアクセス"
echo "3. プライベートサブネットでの実行"
echo "4. https://demo1.cc.cm-ga.me でアクセス確認"
echo ""
echo "=== 追加確認コマンド ==="
echo "ログ監視: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"
echo "診断実行: ./diagnose-demo.sh"