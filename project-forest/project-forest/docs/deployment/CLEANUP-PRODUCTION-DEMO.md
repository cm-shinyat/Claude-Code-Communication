# Project Forest デモ環境リソース削除ガイド

本格デモ環境で作成したすべてのAWSリソースを安全に削除する手順です。

## ⚠️ 重要な注意事項

- **データが完全に失われます** - RDSのデータは復旧できません
- **削除は不可逆的です** - 誤って削除すると元に戻せません
- **依存関係の順序** - 正しい順序で削除しないとエラーが発生します

## 🚀 クイック削除スクリプト

すべてを自動で削除する場合：

```bash
./cleanup-production-demo.sh
```

## 📋 手動削除手順

### ステップ 1: ECSサービス・クラスター削除

```bash
PROJECT_NAME="project-forest-demo"
REGION="ap-northeast-1"

# ECSサービス削除
aws-vault exec shinyat -- aws ecs update-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --desired-count 0 \
  --region $REGION

aws-vault exec shinyat -- aws ecs delete-service \
  --cluster ${PROJECT_NAME}-cluster \
  --service ${PROJECT_NAME}-service \
  --force \
  --region $REGION

# ECSクラスター削除
aws-vault exec shinyat -- aws ecs delete-cluster \
  --cluster ${PROJECT_NAME}-cluster \
  --region $REGION
```

### ステップ 2: Application Load Balancer削除

```bash
# ALB ARNを取得
ALB_ARN=$(aws-vault exec shinyat -- aws elbv2 describe-load-balancers \
  --names ${PROJECT_NAME}-alb \
  --region $REGION \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text 2>/dev/null)

if [[ "$ALB_ARN" != "None" ]] && [[ -n "$ALB_ARN" ]]; then
  # リスナー削除
  LISTENER_ARNS=$(aws-vault exec shinyat -- aws elbv2 describe-listeners \
    --load-balancer-arn $ALB_ARN \
    --region $REGION \
    --query "Listeners[].ListenerArn" \
    --output text)
  
  for LISTENER_ARN in $LISTENER_ARNS; do
    aws-vault exec shinyat -- aws elbv2 delete-listener \
      --listener-arn $LISTENER_ARN \
      --region $REGION
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
      --region $REGION
  fi
  
  # ALB削除
  aws-vault exec shinyat -- aws elbv2 delete-load-balancer \
    --load-balancer-arn $ALB_ARN \
    --region $REGION
fi
```

### ステップ 3: RDS削除

```bash
# RDSインスタンス削除（最終スナップショット作成）
aws-vault exec shinyat -- aws rds delete-db-instance \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --final-db-snapshot-identifier ${PROJECT_NAME}-db-final-snapshot-$(date +%Y%m%d) \
  --region $REGION

# RDS削除完了を待機
aws-vault exec shinyat -- aws rds wait db-instance-deleted \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --region $REGION

# DBサブネットグループ削除
aws-vault exec shinyat -- aws rds delete-db-subnet-group \
  --db-subnet-group-name ${PROJECT_NAME}-db-subnet-group \
  --region $REGION
```

### ステップ 4: Route 53レコード削除

```bash
HOSTED_ZONE_ID="Z1234567890123"  # あなたのホストゾーンID
DOMAIN_NAME="demo.project-forest.com"

# Aレコード削除
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
          \"DNSName\": \"YOUR_ALB_DNS_NAME\",
          \"EvaluateTargetHealth\": false
        }
      }
    }]
  }" \
  --region $REGION
```

### ステップ 5: SSL証明書削除

```bash
# 証明書ARNを取得
CERTIFICATE_ARN=$(aws-vault exec shinyat -- aws acm list-certificates \
  --region $REGION \
  --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" \
  --output text)

if [[ -n "$CERTIFICATE_ARN" ]] && [[ "$CERTIFICATE_ARN" != "None" ]]; then
  aws-vault exec shinyat -- aws acm delete-certificate \
    --certificate-arn $CERTIFICATE_ARN \
    --region $REGION
fi
```

### ステップ 6: IAMロール・ポリシー削除

```bash
# ポリシーのデタッチ
aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ${PROJECT_NAME}-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)
aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ${PROJECT_NAME}-execution-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${PROJECT_NAME}-secrets-policy

# カスタムポリシー削除
aws-vault exec shinyat -- aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${PROJECT_NAME}-secrets-policy

# ロール削除
aws-vault exec shinyat -- aws iam delete-role \
  --role-name ${PROJECT_NAME}-execution-role
```

### ステップ 7: Secrets Manager削除

```bash
# シークレット削除
SECRET_ARN=$(aws-vault exec shinyat -- aws secretsmanager describe-secret \
  --secret-id ${PROJECT_NAME}/database \
  --region $REGION \
  --query "ARN" \
  --output text 2>/dev/null)

if [[ -n "$SECRET_ARN" ]] && [[ "$SECRET_ARN" != "None" ]]; then
  aws-vault exec shinyat -- aws secretsmanager delete-secret \
    --secret-id $SECRET_ARN \
    --force-delete-without-recovery \
    --region $REGION
fi
```

### ステップ 8: ECR削除

```bash
# ECRリポジトリ削除
aws-vault exec shinyat -- aws ecr delete-repository \
  --repository-name project-forest \
  --force \
  --region $REGION
```

### ステップ 9: CloudWatchログ削除

```bash
# ロググループ削除
aws-vault exec shinyat -- aws logs delete-log-group \
  --log-group-name /ecs/${PROJECT_NAME} \
  --region $REGION
```

### ステップ 10: セキュリティグループ削除

```bash
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
for SG_ID in $ALB_SG_ID $ECS_SG_ID $RDS_SG_ID; do
  if [[ "$SG_ID" != "None" ]] && [[ -n "$SG_ID" ]]; then
    aws-vault exec shinyat -- aws ec2 delete-security-group \
      --group-id $SG_ID \
      --region $REGION
  fi
done
```

### ステップ 11: VPCリソース削除

```bash
# VPC ID取得
VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION 2>/dev/null)

if [[ "$VPC_ID" != "None" ]] && [[ -n "$VPC_ID" ]]; then
  # サブネット削除
  SUBNET_IDS=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[].SubnetId" \
    --output text \
    --region $REGION)
  
  for SUBNET_ID in $SUBNET_IDS; do
    aws-vault exec shinyat -- aws ec2 delete-subnet \
      --subnet-id $SUBNET_ID \
      --region $REGION
  done
  
  # ルートテーブル削除
  ROUTE_TABLE_IDS=$(aws-vault exec shinyat -- aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-public-rt" \
    --query "RouteTables[].RouteTableId" \
    --output text \
    --region $REGION)
  
  for RT_ID in $ROUTE_TABLE_IDS; do
    aws-vault exec shinyat -- aws ec2 delete-route-table \
      --route-table-id $RT_ID \
      --region $REGION
  done
  
  # インターネットゲートウェイのデタッチ・削除
  IGW_ID=$(aws-vault exec shinyat -- aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[0].InternetGatewayId" \
    --output text \
    --region $REGION)
  
  if [[ "$IGW_ID" != "None" ]] && [[ -n "$IGW_ID" ]]; then
    aws-vault exec shinyat -- aws ec2 detach-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --vpc-id $VPC_ID \
      --region $REGION
    
    aws-vault exec shinyat -- aws ec2 delete-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --region $REGION
  fi
  
  # VPC削除
  aws-vault exec shinyat -- aws ec2 delete-vpc \
    --vpc-id $VPC_ID \
    --region $REGION
fi
```

## 🔍 削除確認

すべてのリソースが削除されたことを確認：

```bash
# ECS確認
aws-vault exec shinyat -- aws ecs list-clusters --region $REGION

# ALB確認
aws-vault exec shinyat -- aws elbv2 describe-load-balancers --region $REGION

# RDS確認
aws-vault exec shinyat -- aws rds describe-db-instances --region $REGION

# VPC確認
aws-vault exec shinyat -- aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" --region $REGION
```

## 💰 料金について

削除後も以下の料金が発生する可能性があります：

- **RDSスナップショット**: 削除するまで課金継続
- **CloudWatch Logs**: ログの保存期間分
- **Route 53 ホストゾーン**: ドメイン自体の料金

### スナップショット削除

```bash
# スナップショット一覧確認
aws-vault exec shinyat -- aws rds describe-db-snapshots \
  --db-instance-identifier ${PROJECT_NAME}-db \
  --region $REGION

# 不要なスナップショット削除
aws-vault exec shinyat -- aws rds delete-db-snapshot \
  --db-snapshot-identifier ${PROJECT_NAME}-db-final-snapshot-YYYYMMDD \
  --region $REGION
```

## ✅ 削除チェックリスト

- [ ] ECSサービス・クラスター削除済み
- [ ] ALB・ターゲットグループ削除済み
- [ ] RDS削除済み（スナップショット確認）
- [ ] Route 53レコード削除済み
- [ ] SSL証明書削除済み
- [ ] IAMロール・ポリシー削除済み
- [ ] Secrets Manager削除済み
- [ ] ECRリポジトリ削除済み
- [ ] CloudWatchログ削除済み
- [ ] セキュリティグループ削除済み
- [ ] VPCリソース削除済み
- [ ] 請求額の確認（翌日以降）

## 🚨 トラブルシューティング

### 依存関係エラー

```
DependencyViolation: resource has a dependent object
```

**解決方法**: 依存するリソースを先に削除してから再試行

### セキュリティグループ削除エラー

```
InvalidGroup.InUse: Group is used by security group rule
```

**解決方法**: セキュリティグループ間の参照を削除してから再試行

### VPC削除エラー

```
DependencyViolation: The vpc has dependencies and cannot be deleted
```

**解決方法**: ENI、セキュリティグループ、サブネットなどをすべて削除してから再試行

これで完全にクリーンアップできます！