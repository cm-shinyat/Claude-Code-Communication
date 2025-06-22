# Project Forest ALBを使用した安全なデプロイガイド

インターネットからアクセス可能で、かつセキュアな構成を実現します。

## アーキテクチャ

### 現在の構成（推奨されない）
```
インターネット
    ↓
[セキュリティグループ: ポート3000を特定IPから許可]
    ↓
ECS Fargateタスク（パブリックIP付き）
```

### 推奨構成（ALB使用）
```
インターネット
    ↓
[ALB用セキュリティグループ: 80/443を0.0.0.0/0から許可]
    ↓
Application Load Balancer
    ↓
[アプリ用セキュリティグループ: 3000をALBからのみ許可]
    ↓
ECS Fargateタスク（プライベートIP）
```

## ステップバイステップ実装

### ステップ 1: ALB用セキュリティグループ作成

```bash
# ALB用セキュリティグループ作成
ALB_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name project-forest-alb-sg \
  --description "Security group for Project Forest ALB" \
  --vpc-id $VPC_ID \
  --query "GroupId" \
  --output text \
  --region ap-northeast-1)

# HTTP(80)を全インターネットから許可
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-1 \
  --group-rule-description "Allow HTTP from anywhere"

# HTTPS(443)を全インターネットから許可（SSL証明書がある場合）
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-1 \
  --group-rule-description "Allow HTTPS from anywhere"
```

### ステップ 2: アプリ用セキュリティグループ作成

```bash
# アプリ用セキュリティグループ作成
APP_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
  --group-name project-forest-app-sg \
  --description "Security group for Project Forest ECS tasks" \
  --vpc-id $VPC_ID \
  --query "GroupId" \
  --output text \
  --region ap-northeast-1)

# ポート3000をALBのセキュリティグループからのみ許可
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $APP_SG_ID \
  --protocol tcp \
  --port 3000 \
  --source-group $ALB_SG_ID \
  --region ap-northeast-1 \
  --group-rule-description "Allow port 3000 from ALB only"
```

### ステップ 3: ALB作成

```bash
# ALB作成
ALB_ARN=$(aws-vault exec shinyat -- aws elbv2 create-load-balancer \
  --name project-forest-alb \
  --subnets $SUBNET_1 $SUBNET_2 \
  --security-groups $ALB_SG_ID \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --region ap-northeast-1 \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text)

# ターゲットグループ作成
TG_ARN=$(aws-vault exec shinyat -- aws elbv2 create-target-group \
  --name project-forest-tg \
  --protocol HTTP \
  --port 3000 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-enabled \
  --health-check-path /api/health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --region ap-northeast-1 \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text)

# リスナー作成
aws-vault exec shinyat -- aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region ap-northeast-1
```

### ステップ 4: ECSサービスをALB対応に更新

```bash
# ECSサービスを削除して再作成（ALB対応）
aws-vault exec shinyat -- aws ecs delete-service \
  --cluster default \
  --service project-forest-dev \
  --force \
  --region ap-northeast-1

# 新しいサービスを作成（ALBと連携）
aws-vault exec shinyat -- aws ecs create-service \
  --cluster default \
  --service-name project-forest-dev \
  --task-definition project-forest-dev \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[\"$SUBNET_1\",\"$SUBNET_2\"],
    securityGroups=[\"$APP_SG_ID\"],
    assignPublicIp=\"DISABLED\"
  }" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=project-forest,containerPort=3000" \
  --region ap-northeast-1
```

### ステップ 5: ALBのDNS名でアクセス

```bash
# ALBのDNS名を取得
ALB_DNS=$(aws-vault exec shinyat -- aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --region ap-northeast-1 \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo "アプリケーションURL: http://$ALB_DNS"
```

## クイックデプロイスクリプト

すべてを自動化したい場合：

```bash
#!/bin/bash
# deploy-with-alb.sh

set -e

# 変数設定
REGION="ap-northeast-1"
VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region $REGION)
SUBNET_1=$(aws-vault exec shinyat -- aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=${REGION}a" --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" --output text --region $REGION | head -1)
SUBNET_2=$(aws-vault exec shinyat -- aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=${REGION}c" --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" --output text --region $REGION | head -1)

echo "🚀 ALBを使用した安全なデプロイを開始..."

# 1. セキュリティグループ作成
echo "🛡️ セキュリティグループ作成中..."
# ALB用
ALB_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group --group-name project-forest-alb-sg --description "ALB SG" --vpc-id $VPC_ID --query "GroupId" --output text --region $REGION)
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION

# アプリ用
APP_SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group --group-name project-forest-app-sg --description "App SG" --vpc-id $VPC_ID --query "GroupId" --output text --region $REGION)
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress --group-id $APP_SG_ID --protocol tcp --port 3000 --source-group $ALB_SG_ID --region $REGION

# 2. ALB作成
echo "⚖️ ALB作成中..."
ALB_ARN=$(aws-vault exec shinyat -- aws elbv2 create-load-balancer --name project-forest-alb --subnets $SUBNET_1 $SUBNET_2 --security-groups $ALB_SG_ID --region $REGION --query "LoadBalancers[0].LoadBalancerArn" --output text)

# 3. ターゲットグループ作成
TG_ARN=$(aws-vault exec shinyat -- aws elbv2 create-target-group --name project-forest-tg --protocol HTTP --port 3000 --vpc-id $VPC_ID --target-type ip --region $REGION --query "TargetGroups[0].TargetGroupArn" --output text)

# 4. リスナー作成
aws-vault exec shinyat -- aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN --region $REGION

# 5. ECSサービス作成
echo "📦 ECSサービス作成中..."
aws-vault exec shinyat -- aws ecs create-service \
  --cluster default \
  --service-name project-forest-dev \
  --task-definition project-forest-dev \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[\"$SUBNET_1\",\"$SUBNET_2\"],securityGroups=[\"$APP_SG_ID\"],assignPublicIp=\"DISABLED\"}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=project-forest,containerPort=3000" \
  --region $REGION

# 6. URL表示
ALB_DNS=$(aws-vault exec shinyat -- aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $REGION --query "LoadBalancers[0].DNSName" --output text)
echo "✅ デプロイ完了！"
echo "🌐 アプリケーションURL: http://$ALB_DNS"
```

## メリット

### セキュリティ面
- ✅ アプリケーションが直接インターネットに露出しない
- ✅ 標準的なHTTP/HTTPSポートを使用
- ✅ Security Hubのアラートが出ない
- ✅ ALBレベルでWAFやアクセスログを設定可能

### 運用面
- ✅ 複数のECSタスクにロードバランシング可能
- ✅ SSL証明書の管理が簡単（ALBに設定）
- ✅ ヘルスチェックが充実
- ✅ Blue/Greenデプロイが可能

### コスト
- ⚠️ ALBの料金が追加（月額約$20〜）
- 💡 開発環境では必要な時だけ起動することでコスト削減可能

## カスタムドメインの設定（オプション）

Route 53を使用してカスタムドメインを設定：

```bash
# Route 53でAレコードを作成
aws-vault exec shinyat -- aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "dev.project-forest.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z14GRHDCWA56QT",
          "DNSName": "'$ALB_DNS'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

## まとめ

現在の構成はECSタスクに直接アクセスしていますが、本来は：

1. **開発環境でも**：ALB経由でアクセスするのが推奨
2. **本番環境では必須**：ALBなしでの直接公開は避けるべき
3. **コストが気になる場合**：開発時のみ現在の構成を使い、本番はALB必須

どちらの構成を選ぶか教えていただければ、具体的な実装をサポートします！