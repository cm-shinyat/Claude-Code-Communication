#!/usr/bin/env zsh
# ECS Draining状態を待機してからサービス再作成

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

echo "${BLUE}⏳ ECS Draining状態の解決${NC}"
echo ""

# 1. サービスの完全削除を待機
echo "${YELLOW}🕐 ステップ 1: サービス削除完了を待機${NC}"

MAX_WAIT=600  # 10分間待機
WAIT_COUNT=0

while [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
  SERVICE_STATUS=$(aws-vault exec shinyat -- aws ecs describe-services \
    --cluster ${PROJECT_NAME}-cluster \
    --services ${PROJECT_NAME}-service \
    --region $REGION \
    --query "services[0].status" \
    --output text 2>/dev/null || echo "MISSING")
  
  if [[ "$SERVICE_STATUS" == "MISSING" ]] || [[ "$SERVICE_STATUS" == "None" ]]; then
    echo "${GREEN}✅ サービスが完全に削除されました${NC}"
    break
  fi
  
  echo "サービス状態: $SERVICE_STATUS (${WAIT_COUNT}秒経過)"
  sleep 30
  WAIT_COUNT=$((WAIT_COUNT + 30))
done

if [[ $WAIT_COUNT -ge $MAX_WAIT ]]; then
  echo "${RED}❌ タイムアウト: サービス削除が完了しませんでした${NC}"
  echo "手動でサービスを強制削除してください："
  echo "aws-vault exec shinyat -- aws ecs delete-service --cluster ${PROJECT_NAME}-cluster --service ${PROJECT_NAME}-service --force --region $REGION"
  exit 1
fi

# 2. タスクが完全に停止するまで待機
echo ""
echo "${YELLOW}📦 ステップ 2: タスク停止完了を待機${NC}"

TASK_WAIT=0
while [[ $TASK_WAIT -lt 300 ]]; do  # 5分間待機
  RUNNING_TASKS=$(aws-vault exec shinyat -- aws ecs list-tasks \
    --cluster ${PROJECT_NAME}-cluster \
    --region $REGION \
    --query "length(taskArns)" \
    --output text 2>/dev/null || echo "0")
  
  if [[ "$RUNNING_TASKS" -eq 0 ]]; then
    echo "${GREEN}✅ すべてのタスクが停止しました${NC}"
    break
  fi
  
  echo "実行中のタスク数: $RUNNING_TASKS (${TASK_WAIT}秒経過)"
  sleep 30
  TASK_WAIT=$((TASK_WAIT + 30))
done

# 3. 必要な情報を取得
echo ""
echo "${YELLOW}📋 ステップ 3: リソース情報取得${NC}"

VPC_ID="vpc-0eb889d242976f7c2"
PRIVATE_SUBNET_1="subnet-045327644d0d5e5df"
PRIVATE_SUBNET_2="subnet-068d374080c7f3de6"
ECS_SG_ID="sg-00cabac718b3d77b0"

TARGET_GROUP_ARN=$(aws-vault exec shinyat -- aws elbv2 describe-target-groups \
  --names ${PROJECT_NAME}-tg \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text \
  --region $REGION)

echo "Target Group ARN: $TARGET_GROUP_ARN"

# 4. 新しいサービスを作成
echo ""
echo "${YELLOW}🚀 ステップ 4: 新しいサービス作成${NC}"

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

if [[ $? -eq 0 ]]; then
  echo "${GREEN}✅ サービス作成成功${NC}"
else
  echo "${RED}❌ サービス作成失敗${NC}"
  exit 1
fi

# 5. サービス起動確認
echo ""
echo "${YELLOW}⏳ ステップ 5: サービス起動確認${NC}"
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

# 6. タスク詳細確認
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
      --query "tasks[0].{LastStatus:lastStatus,HealthStatus:healthStatus,StoppedReason:stoppedReason}" \
      --output table 2>/dev/null)
    
    echo "タスク状態:"
    echo "$TASK_STATUS"
    
    # エラーがある場合は詳細表示
    STOPPED_REASON=$(aws-vault exec shinyat -- aws ecs describe-tasks \
      --cluster ${PROJECT_NAME}-cluster \
      --tasks $FIRST_TASK \
      --region $REGION \
      --query "tasks[0].stoppedReason" \
      --output text 2>/dev/null)
    
    if [[ -n "$STOPPED_REASON" ]] && [[ "$STOPPED_REASON" != "None" ]] && [[ "$STOPPED_REASON" != "null" ]]; then
      echo ""
      echo "${RED}タスク停止理由: $STOPPED_REASON${NC}"
    fi
  fi
else
  echo "${RED}❌ 実行中のタスクがありません${NC}"
fi

# 7. 最新ログ確認
echo ""
echo "${YELLOW}📝 ステップ 6: 最新ログ確認${NC}"
echo "最新のログ（最大15行）:"
aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} \
  --since 5m \
  --region $REGION 2>/dev/null | tail -15 || echo "ログが見つかりません"

echo ""
echo "${GREEN}🎉 サービス再作成完了${NC}"
echo ""
echo "=== 次の確認事項 ==="
echo "1. VPCエンドポイントが正しく作成されているか"
echo "2. タスクでSecrets Managerエラーが解消されているか"
echo "3. アプリケーションが正常に起動しているか"
echo ""
echo "=== 追加コマンド ==="
echo "VPCエンドポイント修正: ./fix-vpc-endpoints.sh"
echo "ログ監視: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"
echo "診断実行: ./diagnose-demo.sh"