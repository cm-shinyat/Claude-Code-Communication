#!/bin/bash
# Project Forest AWS リソース完全削除スクリプト

set -e

# 色の定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "${RED}🗑️  Project Forest リソースを完全削除します...${NC}"
echo "${YELLOW}⚠️  この操作は取り消せません！${NC}"
echo "${YELLOW}⚠️  すべてのデータとリソースが永続的に削除されます！${NC}"
echo ""
echo "削除対象："
echo "- ECSサービス: project-forest-dev"
echo "- ECSタスク定義: project-forest-dev"
echo "- ECRリポジトリ: project-forest"
echo "- CloudWatchログ: /ecs/project-forest-dev"
echo "- セキュリティグループ: project-forest-dev-sg"
echo "- IAMロール: ecsTaskExecutionRole"
echo ""

# 確認プロンプト
read -p "本当に削除しますか？ (yes/no): " confirm
if [[ $confirm != "yes" ]]; then
    echo "削除をキャンセルしました。"
    exit 0
fi

echo ""
echo "${YELLOW}5秒後に削除を開始します...${NC}"
sleep 5

REGION="ap-northeast-1"

# ステップ 1: ECSサービス削除
echo "${YELLOW}📱 ECSサービスを削除中...${NC}"
aws-vault exec shinyat -- aws ecs delete-service \
  --cluster default \
  --service project-forest-dev \
  --force \
  --region $REGION 2>/dev/null && echo "✅ ECSサービス削除完了" || echo "ℹ️  サービスが存在しないか既に削除済み"

# ステップ 2: タスク定義登録解除
echo "${YELLOW}📋 ECSタスク定義を登録解除中...${NC}"
TASK_DEFS=$(aws-vault exec shinyat -- aws ecs list-task-definitions \
  --family-prefix project-forest-dev \
  --region $REGION \
  --query "taskDefinitionArns" \
  --output text 2>/dev/null)

task_count=0
for task_def in $TASK_DEFS; do
  if [ -n "$task_def" ] && [ "$task_def" != "None" ]; then
    aws-vault exec shinyat -- aws ecs deregister-task-definition \
      --task-definition $task_def \
      --region $REGION > /dev/null
    task_count=$((task_count + 1))
  fi
done
echo "✅ タスク定義 ${task_count}個を登録解除完了"

# ステップ 3: ECRリポジトリ削除
echo "${YELLOW}📦 ECRリポジトリを削除中...${NC}"
aws-vault exec shinyat -- aws ecr delete-repository \
  --repository-name project-forest \
  --force \
  --region $REGION 2>/dev/null && echo "✅ ECRリポジトリ削除完了" || echo "ℹ️  リポジトリが存在しないか既に削除済み"

# ステップ 4: CloudWatchログ削除
echo "${YELLOW}📝 CloudWatchログを削除中...${NC}"
aws-vault exec shinyat -- aws logs delete-log-group \
  --log-group-name /ecs/project-forest-dev \
  --region $REGION 2>/dev/null && echo "✅ CloudWatchログ削除完了" || echo "ℹ️  ログループが存在しないか既に削除済み"

# ステップ 5: セキュリティグループ削除
echo "${YELLOW}🛡️  セキュリティグループを削除中...${NC}"
SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=project-forest-dev-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION 2>/dev/null)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  aws-vault exec shinyat -- aws ec2 delete-security-group \
    --group-id $SG_ID \
    --region $REGION 2>/dev/null && echo "✅ セキュリティグループ削除完了" || echo "⚠️  セキュリティグループ削除に失敗（使用中の可能性があります）"
else
  echo "ℹ️  セキュリティグループが存在しないか既に削除済み"
fi

# ステップ 6: IAMロール削除
echo "${YELLOW}👤 IAMロールとポリシーを削除中...${NC}"

# ポリシーをデタッチ
aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  2>/dev/null || true

aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  2>/dev/null || true

# ロールを削除
aws-vault exec shinyat -- aws iam delete-role \
  --role-name ecsTaskExecutionRole \
  2>/dev/null && echo "✅ IAMロール削除完了" || echo "ℹ️  ロールが存在しないか既に削除済み"

# ユーザーポリシー削除
USER_NAME=$(aws-vault exec shinyat -- aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)
aws-vault exec shinyat -- aws iam delete-user-policy \
  --user-name $USER_NAME \
  --policy-name ECSPassRolePolicy \
  2>/dev/null && echo "✅ ユーザーポリシー削除完了" || echo "ℹ️  ユーザーポリシーが存在しないか既に削除済み"

# 削除確認
echo ""
echo "${GREEN}🔍 削除確認中...${NC}"

echo ""
echo "=== ECSサービス ==="
SERVICES=$(aws-vault exec shinyat -- aws ecs list-services --cluster default --region $REGION --query "serviceArns" --output text 2>/dev/null)
if [ -z "$SERVICES" ] || [ "$SERVICES" = "None" ]; then
  echo "✅ ECSサービスなし（正常）"
else
  echo "⚠️  残存するECSサービス: $SERVICES"
fi

echo ""
echo "=== ECRリポジトリ ==="
REPOS=$(aws-vault exec shinyat -- aws ecr describe-repositories --region $REGION --query "repositories[?repositoryName=='project-forest'].repositoryName" --output text 2>/dev/null)
if [ -z "$REPOS" ] || [ "$REPOS" = "None" ]; then
  echo "✅ project-forestリポジトリなし（正常）"
else
  echo "⚠️  残存するリポジトリ: $REPOS"
fi

echo ""
echo "=== CloudWatchログ ==="
LOGS=$(aws-vault exec shinyat -- aws logs describe-log-groups --log-group-name-prefix "/ecs/project-forest" --region $REGION --query "logGroups[].logGroupName" --output text 2>/dev/null)
if [ -z "$LOGS" ] || [ "$LOGS" = "None" ]; then
  echo "✅ project-forest関連ログなし（正常）"
else
  echo "⚠️  残存するログループ: $LOGS"
fi

echo ""
echo "=== セキュリティグループ ==="
SGS=$(aws-vault exec shinyat -- aws ec2 describe-security-groups --filters "Name=group-name,Values=project-forest-dev-sg" --region $REGION --query "SecurityGroups[].GroupId" --output text 2>/dev/null)
if [ -z "$SGS" ] || [ "$SGS" = "None" ]; then
  echo "✅ project-forest-dev-sgなし（正常）"
else
  echo "⚠️  残存するセキュリティグループ: $SGS"
fi

echo ""
echo "=== IAMロール ==="
ROLE_EXISTS=$(aws-vault exec shinyat -- aws iam get-role --role-name ecsTaskExecutionRole 2>/dev/null && echo "exists" || echo "not_exists")
if [ "$ROLE_EXISTS" = "not_exists" ]; then
  echo "✅ ecsTaskExecutionRoleなし（正常）"
else
  echo "⚠️  ecsTaskExecutionRoleが残存しています"
fi

echo ""
echo "${GREEN}🎉 削除処理完了！${NC}"
echo ""
echo "${YELLOW}📊 課金確認のお願い：${NC}"
echo "1. AWS Cost Explorer で以下のサービスの課金がないことを確認："
echo "   - Amazon Elastic Container Service"
echo "   - Amazon Elastic Container Registry"  
echo "   - Amazon CloudWatch"
echo "   - Amazon EC2"
echo ""
echo "2. 数日間課金状況を監視してください"
echo ""
echo "${GREEN}✅ Project Forest リソースの削除が完了しました！${NC}"