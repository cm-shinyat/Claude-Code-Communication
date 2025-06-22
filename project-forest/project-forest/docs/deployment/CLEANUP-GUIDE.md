# Project Forest AWS リソース完全削除ガイド

開発環境で作成したAWSリソースを完全に削除するための手順書です。**課金を止めたい場合や環境をリセットしたい場合に使用してください。**

⚠️ **警告**: この手順を実行すると、すべてのデータとリソースが**永続的に削除**されます。本番環境では絶対に実行しないでください。

## 前提条件

- aws-vault がセットアップ済み
- 削除対象のAWSアカウントへのアクセス権限

## 削除順序（重要）

AWSリソースには依存関係があるため、以下の順序で削除する必要があります：

1. ECSサービス
2. ECSタスク定義
3. ECRリポジトリ
4. CloudWatchログ
5. セキュリティグループ
6. IAMロール・ポリシー
7. VPC（カスタムVPCを作成した場合のみ）

## ステップ 1: 事前確認

```bash
# 現在のリソース状況を確認
echo "=== アカウント情報 ==="
aws-vault exec shinyat -- aws sts get-caller-identity

echo "=== ECSクラスター一覧 ==="
aws-vault exec shinyat -- aws ecs list-clusters --region ap-northeast-1

echo "=== ECSサービス一覧 ==="
aws-vault exec shinyat -- aws ecs list-services --cluster default --region ap-northeast-1

echo "=== ECRリポジトリ一覧 ==="
aws-vault exec shinyat -- aws ecr describe-repositories --region ap-northeast-1 --query "repositories[].repositoryName"
```

## ステップ 2: ECSサービスの削除

```bash
# ECSサービスを削除
echo "🗑️  ECSサービスを削除中..."
aws-vault exec shinyat -- aws ecs delete-service \
  --cluster default \
  --service project-forest-dev \
  --force \
  --region ap-northeast-1 2>/dev/null || echo "サービスが存在しないか既に削除済み"

# 削除完了を待機
echo "⏳ サービス削除完了を待機中..."
aws-vault exec shinyat -- aws ecs wait services-inactive \
  --cluster default \
  --services project-forest-dev \
  --region ap-northeast-1 2>/dev/null || echo "待機完了またはサービスが存在しません"
```

## ステップ 3: ECSタスク定義の登録解除

```bash
# タスク定義の一覧を取得
echo "📋 タスク定義を登録解除中..."
TASK_DEFINITIONS=$(aws-vault exec shinyat -- aws ecs list-task-definitions \
  --family-prefix project-forest-dev \
  --region ap-northeast-1 \
  --query "taskDefinitionArns" \
  --output text)

# 各タスク定義を登録解除
for task_def in $TASK_DEFINITIONS; do
  if [ -n "$task_def" ] && [ "$task_def" != "None" ]; then
    echo "登録解除中: $task_def"
    aws-vault exec shinyat -- aws ecs deregister-task-definition \
      --task-definition $task_def \
      --region ap-northeast-1 > /dev/null
  fi
done
```

## ステップ 4: ECRリポジトリの削除

```bash
# ECRリポジトリを削除（全イメージも含む）
echo "📦 ECRリポジトリを削除中..."
aws-vault exec shinyat -- aws ecr delete-repository \
  --repository-name project-forest \
  --force \
  --region ap-northeast-1 2>/dev/null || echo "リポジトリが存在しないか既に削除済み"
```

## ステップ 5: CloudWatchログの削除

```bash
# ログループを削除
echo "📝 CloudWatchログループを削除中..."
aws-vault exec shinyat -- aws logs delete-log-group \
  --log-group-name /ecs/project-forest-dev \
  --region ap-northeast-1 2>/dev/null || echo "ログループが存在しないか既に削除済み"

# 関連する他のログループも削除
LOG_GROUPS=$(aws-vault exec shinyat -- aws logs describe-log-groups \
  --log-group-name-prefix "/ecs/project-forest" \
  --region ap-northeast-1 \
  --query "logGroups[].logGroupName" \
  --output text 2>/dev/null)

for log_group in $LOG_GROUPS; do
  if [ -n "$log_group" ] && [ "$log_group" != "None" ]; then
    echo "削除中: $log_group"
    aws-vault exec shinyat -- aws logs delete-log-group \
      --log-group-name $log_group \
      --region ap-northeast-1 2>/dev/null || true
  fi
done
```

## ステップ 6: セキュリティグループの削除

```bash
# Project Forest用のセキュリティグループを削除
echo "🛡️  セキュリティグループを削除中..."

# セキュリティグループIDを取得
SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=project-forest-dev-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region ap-northeast-1 2>/dev/null)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "削除中: $SG_ID"
  aws-vault exec shinyat -- aws ec2 delete-security-group \
    --group-id $SG_ID \
    --region ap-northeast-1 2>/dev/null || echo "削除に失敗しました（使用中の可能性があります）"
else
  echo "セキュリティグループが存在しないか既に削除済み"
fi
```

## ステップ 7: IAMロールとポリシーの削除

```bash
# IAMロールから添付されているポリシーをデタッチ
echo "👤 IAMロールとポリシーを削除中..."

# ecsTaskExecutionRoleからポリシーをデタッチ
aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  2>/dev/null || echo "ポリシーが既にデタッチ済みまたは存在しません"

aws-vault exec shinyat -- aws iam detach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  2>/dev/null || echo "ポリシーが既にデタッチ済みまたは存在しません"

# IAMロールを削除
aws-vault exec shinyat -- aws iam delete-role \
  --role-name ecsTaskExecutionRole \
  2>/dev/null || echo "ロールが存在しないか既に削除済み"

# ユーザーのインラインポリシーを削除
USER_NAME=$(aws-vault exec shinyat -- aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)
aws-vault exec shinyat -- aws iam delete-user-policy \
  --user-name $USER_NAME \
  --policy-name ECSPassRolePolicy \
  2>/dev/null || echo "ユーザーポリシーが存在しないか既に削除済み"
```

## ステップ 8: 残存リソースの確認

```bash
# 削除確認
echo "✅ 削除確認中..."

echo "=== ECSサービス（空であることを確認） ==="
aws-vault exec shinyat -- aws ecs list-services --cluster default --region ap-northeast-1

echo "=== ECRリポジトリ（project-forestが存在しないことを確認） ==="
aws-vault exec shinyat -- aws ecr describe-repositories --region ap-northeast-1 --query "repositories[].repositoryName" 2>/dev/null || echo "リポジトリなし"

echo "=== CloudWatchログ（project-forest関連が存在しないことを確認） ==="
aws-vault exec shinyat -- aws logs describe-log-groups --log-group-name-prefix "/ecs/project-forest" --region ap-northeast-1 --query "logGroups[].logGroupName" 2>/dev/null || echo "ログループなし"

echo "=== セキュリティグループ（project-forest-dev-sgが存在しないことを確認） ==="
aws-vault exec shinyat -- aws ec2 describe-security-groups --filters "Name=group-name,Values=project-forest-dev-sg" --region ap-northeast-1 --query "SecurityGroups[].GroupId" 2>/dev/null || echo "セキュリティグループなし"

echo "=== IAMロール（ecsTaskExecutionRoleが存在しないことを確認） ==="
aws-vault exec shinyat -- aws iam get-role --role-name ecsTaskExecutionRole 2>/dev/null || echo "ロールが存在しません（正常）"
```

## 完全削除スクリプト（ワンライナー）

すべてを一度に削除したい場合は、以下のスクリプトを使用できます：

```bash
#!/bin/bash
# Project Forest リソース完全削除スクリプト

set -e

echo "🗑️  Project Forest リソースを完全削除します..."
echo "⚠️  この操作は取り消せません。5秒後に開始します..."
sleep 5

# ECSサービス削除
aws-vault exec shinyat -- aws ecs delete-service --cluster default --service project-forest-dev --force --region ap-northeast-1 2>/dev/null || true

# タスク定義登録解除
TASK_DEFS=$(aws-vault exec shinyat -- aws ecs list-task-definitions --family-prefix project-forest-dev --region ap-northeast-1 --query "taskDefinitionArns" --output text)
for task_def in $TASK_DEFS; do
  [ -n "$task_def" ] && [ "$task_def" != "None" ] && aws-vault exec shinyat -- aws ecs deregister-task-definition --task-definition $task_def --region ap-northeast-1 > /dev/null
done

# ECRリポジトリ削除
aws-vault exec shinyat -- aws ecr delete-repository --repository-name project-forest --force --region ap-northeast-1 2>/dev/null || true

# CloudWatchログ削除
aws-vault exec shinyat -- aws logs delete-log-group --log-group-name /ecs/project-forest-dev --region ap-northeast-1 2>/dev/null || true

# セキュリティグループ削除
SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups --filters "Name=group-name,Values=project-forest-dev-sg" --query "SecurityGroups[0].GroupId" --output text --region ap-northeast-1 2>/dev/null)
[ -n "$SG_ID" ] && [ "$SG_ID" != "None" ] && aws-vault exec shinyat -- aws ec2 delete-security-group --group-id $SG_ID --region ap-northeast-1 2>/dev/null || true

# IAMロール削除
aws-vault exec shinyat -- aws iam detach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true
aws-vault exec shinyat -- aws iam detach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true
aws-vault exec shinyat -- aws iam delete-role --role-name ecsTaskExecutionRole 2>/dev/null || true

# ユーザーポリシー削除
USER_NAME=$(aws-vault exec shinyat -- aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)
aws-vault exec shinyat -- aws iam delete-user-policy --user-name $USER_NAME --policy-name ECSPassRolePolicy 2>/dev/null || true

echo "✅ 削除完了！"
```

## 課金確認

削除後は、以下を確認してください：

### AWS Cost Explorer で確認
1. [AWS Cost Explorer](https://console.aws.amazon.com/cost-reports/) にアクセス
2. 「Service」でフィルタリング
3. 以下のサービスの課金がないことを確認：
   - Amazon Elastic Container Service
   - Amazon Elastic Container Registry
   - Amazon CloudWatch
   - Amazon EC2（セキュリティグループ）

### 課金アラート設定（推奨）
```bash
# 課金アラートを設定（$1以上の課金で通知）
aws-vault exec shinyat -- aws cloudwatch put-metric-alarm \
  --alarm-name "BillingAlert" \
  --alarm-description "Alert when billing exceeds $1" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:388450459156:billing-alerts \
  --region us-east-1
```

## トラブルシューティング

### 削除できないリソースがある場合

1. **ECSサービスが削除できない**
   ```bash
   # タスクを強制停止してから再試行
   aws-vault exec shinyat -- aws ecs update-service --cluster default --service project-forest-dev --desired-count 0 --region ap-northeast-1
   sleep 30
   aws-vault exec shinyat -- aws ecs delete-service --cluster default --service project-forest-dev --force --region ap-northeast-1
   ```

2. **セキュリティグループが削除できない**
   ```bash
   # 使用中のインスタンスやネットワークインターフェースを確認
   aws-vault exec shinyat -- aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$SG_ID" --region ap-northeast-1
   ```

3. **IAMロールが削除できない**
   ```bash
   # アタッチされているポリシーを確認
   aws-vault exec shinyat -- aws iam list-attached-role-policies --role-name ecsTaskExecutionRole
   ```

### 隠れたリソースの確認

```bash
# すべてのECSクラスターを確認
aws-vault exec shinyat -- aws ecs list-clusters --region ap-northeast-1

# すべてのECRリポジトリを確認
aws-vault exec shinyat -- aws ecr describe-repositories --region ap-northeast-1

# Project Forest関連のすべてのCloudWatchログを確認
aws-vault exec shinyat -- aws logs describe-log-groups --region ap-northeast-1 | grep -i forest
```

## まとめ

この手順により、Project Forest関連のすべてのAWSリソースが削除され、課金が停止されます。削除は不可逆的な操作なので、実行前に十分確認してください。

**重要**: 削除後は、AWS Cost Explorerで数日間課金状況を監視することをお勧めします。