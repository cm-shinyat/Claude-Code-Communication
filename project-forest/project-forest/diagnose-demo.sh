#!/usr/bin/env zsh
# Project Forest デモ環境 診断スクリプト

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

echo "${BLUE}🔍 Project Forest デモ環境 診断開始${NC}"
echo ""

# 1. ECSサービス状態確認
echo "${YELLOW}📋 ステップ 1: ECSサービス状態確認${NC}"
SERVICE_STATUS=$(aws-vault exec shinyat -- aws ecs describe-services \
  --cluster ${PROJECT_NAME}-cluster \
  --services ${PROJECT_NAME}-service \
  --region $REGION \
  --query "services[0].{DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount,Status:status}" \
  --output table 2>/dev/null)

if [[ $? -eq 0 ]]; then
  echo "$SERVICE_STATUS"
else
  echo "${RED}❌ ECSサービスが見つかりません${NC}"
  exit 1
fi

# 2. タスク状態確認
echo ""
echo "${YELLOW}📦 ステップ 2: ECSタスク状態確認${NC}"
TASK_ARNS=$(aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster ${PROJECT_NAME}-cluster \
  --service-name ${PROJECT_NAME}-service \
  --region $REGION \
  --query "taskArns" \
  --output text 2>/dev/null)

if [[ -n "$TASK_ARNS" ]] && [[ "$TASK_ARNS" != "None" ]]; then
  echo "実行中のタスク数: $(echo $TASK_ARNS | wc -w)"
  
  # 最初のタスクの詳細確認
  FIRST_TASK=$(echo $TASK_ARNS | cut -d' ' -f1)
  echo "タスクARN: $FIRST_TASK"
  
  TASK_STATUS=$(aws-vault exec shinyat -- aws ecs describe-tasks \
    --cluster ${PROJECT_NAME}-cluster \
    --tasks $FIRST_TASK \
    --region $REGION \
    --query "tasks[0].{LastStatus:lastStatus,HealthStatus:healthStatus,StoppedReason:stoppedReason}" \
    --output table 2>/dev/null)
  
  echo "$TASK_STATUS"
else
  echo "${RED}❌ 実行中のタスクがありません${NC}"
fi

# 3. ターゲットグループのヘルス確認
echo ""
echo "${YELLOW}🎯 ステップ 3: ターゲットグループのヘルス確認${NC}"
TG_ARN=$(aws-vault exec shinyat -- aws elbv2 describe-target-groups \
  --names ${PROJECT_NAME}-tg \
  --region $REGION \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text 2>/dev/null)

if [[ -n "$TG_ARN" ]] && [[ "$TG_ARN" != "None" ]]; then
  HEALTH_STATUS=$(aws-vault exec shinyat -- aws elbv2 describe-target-health \
    --target-group-arn $TG_ARN \
    --region $REGION \
    --output table 2>/dev/null)
  
  echo "$HEALTH_STATUS"
  
  # ヘルスチェック設定確認
  HEALTH_CHECK=$(aws-vault exec shinyat -- aws elbv2 describe-target-groups \
    --target-group-arn $TG_ARN \
    --region $REGION \
    --query "TargetGroups[0].{HealthCheckPath:HealthCheckPath,HealthCheckPort:HealthCheckPort,HealthCheckProtocol:HealthCheckProtocol}" \
    --output table)
  
  echo ""
  echo "ヘルスチェック設定:"
  echo "$HEALTH_CHECK"
else
  echo "${RED}❌ ターゲットグループが見つかりません${NC}"
fi

# 4. RDS状態確認
echo ""
echo "${YELLOW}🗄️  ステップ 4: RDS状態確認${NC}"
RDS_STATUS=$(aws-vault exec shinyat -- aws rds describe-db-instances \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --region $REGION \
  --query "DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,MultiAZ:MultiAZ}" \
  --output table 2>/dev/null)

if [[ $? -eq 0 ]]; then
  echo "$RDS_STATUS"
else
  echo "${RED}❌ RDSインスタンスが見つかりません${NC}"
fi

# 5. 最新のログ表示
echo ""
echo "${YELLOW}📝 ステップ 5: 最新ログ確認${NC}"
echo "最新のログ（最大10行）:"
aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} \
  --since 5m \
  --region $REGION 2>/dev/null | tail -10 || echo "ログが見つかりません"

# 6. 推奨対処法の表示
echo ""
echo "${BLUE}💡 推奨対処法:${NC}"
echo ""

# ターゲットヘルス確認
if [[ -n "$TG_ARN" ]]; then
  UNHEALTHY_COUNT=$(aws-vault exec shinyat -- aws elbv2 describe-target-health \
    --target-group-arn $TG_ARN \
    --region $REGION \
    --query "length(TargetHealthDescriptions[?TargetHealth.State!='healthy'])" \
    --output text 2>/dev/null)
  
  if [[ "$UNHEALTHY_COUNT" -gt 0 ]]; then
    echo "${YELLOW}⚠️  ヘルスチェックが失敗しています${NC}"
    echo "対処法:"
    echo "1. ヘルスチェックパスを '/' に変更:"
    echo "   aws-vault exec shinyat -- aws elbv2 modify-target-group --target-group-arn $TG_ARN --health-check-path '/' --region $REGION"
    echo ""
    echo "2. アプリケーションログを確認:"
    echo "   aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"
    echo ""
  fi
fi

# タスクが0個の場合
RUNNING_COUNT=$(echo "$SERVICE_STATUS" | grep -o '[0-9]\+' | head -3 | tail -1 2>/dev/null || echo "0")
if [[ "$RUNNING_COUNT" -eq 0 ]]; then
  echo "${YELLOW}⚠️  実行中のタスクがありません${NC}"
  echo "対処法:"
  echo "1. サービスを再デプロイ:"
  echo "   aws-vault exec shinyat -- aws ecs update-service --cluster ${PROJECT_NAME}-cluster --service ${PROJECT_NAME}-service --force-new-deployment --region $REGION"
  echo ""
  echo "2. タスク定義を確認:"
  echo "   aws-vault exec shinyat -- aws ecs describe-task-definition --task-definition ${PROJECT_NAME}-task --region $REGION"
  echo ""
fi

echo "${GREEN}✅ 診断完了${NC}"
echo ""
echo "詳細なログを確認するには:"
echo "aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow --region $REGION"