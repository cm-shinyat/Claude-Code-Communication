#!/bin/bash
# IPアドレスが変わった時にセキュリティグループを更新するスクリプト

set -e

# 色の定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "${YELLOW}🔄 セキュリティグループのIP更新を開始します...${NC}"

# セキュリティグループ名
SG_NAME="project-forest-dev-sg"
REGION="ap-northeast-1"

# セキュリティグループIDを取得
SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region $REGION 2>/dev/null)

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  echo "${RED}❌ セキュリティグループ '$SG_NAME' が見つかりません${NC}"
  exit 1
fi

echo "Security Group ID: $SG_ID"

# 現在のIPアドレスを取得
NEW_IP=$(curl -s https://checkip.amazonaws.com)
echo "あなたの現在のIP: ${GREEN}$NEW_IP${NC}"

# 既存のルール（ポート3000）を取得
echo "${YELLOW}📋 既存のルールを確認中...${NC}"
OLD_RULES=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissions[?ToPort==\`3000\`].IpRanges[].CidrIp" \
  --output text 2>/dev/null)

# 新しいIPが既に登録されているか確認
if echo "$OLD_RULES" | grep -q "${NEW_IP}/32"; then
  echo "${GREEN}✅ あなたのIP (${NEW_IP}/32) は既に許可されています${NC}"
  exit 0
fi

# 古いルールを削除
if [ -n "$OLD_RULES" ] && [ "$OLD_RULES" != "None" ]; then
  echo "${YELLOW}🗑️  古いルールを削除中...${NC}"
  for OLD_IP in $OLD_RULES; do
    echo "  削除: $OLD_IP"
    aws-vault exec shinyat -- aws ec2 revoke-security-group-ingress \
      --group-id $SG_ID \
      --protocol tcp \
      --port 3000 \
      --cidr $OLD_IP \
      --region $REGION 2>/dev/null || echo "  (既に削除済みかエラー)"
  done
fi

# 新しいルールを追加
echo "${YELLOW}➕ 新しいルールを追加中...${NC}"
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr ${NEW_IP}/32 \
  --region $REGION \
  --group-rule-description "Allow port 3000 from my IP (updated $(date '+%Y-%m-%d'))" \
  && echo "${GREEN}✅ 新しいIP (${NEW_IP}/32) を追加しました${NC}" \
  || echo "${RED}❌ ルールの追加に失敗しました${NC}"

# 更新後の確認
echo ""
echo "${YELLOW}📋 更新後のルール:${NC}"
aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissions[?ToPort==\`3000\`].{Port:ToPort,IPs:IpRanges[].{IP:CidrIp,Description:Description}}" \
  --output table

echo ""
echo "${GREEN}✅ セキュリティグループの更新が完了しました！${NC}"
echo ""
echo "💡 ヒント: IPが頻繁に変わる場合は、このスクリプトを定期的に実行してください。"
echo "   例: crontab -e で以下を追加"
echo "   0 9 * * * /path/to/update-my-ip.sh"