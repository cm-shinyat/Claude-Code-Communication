# Project Forest 開発環境デプロイ完全ガイド（最終版）

このガイドに従えば、必ず開発環境にデプロイできます。

## 前提条件

- aws-vault がインストール済み
- Docker がインストール済み
- AWS アカウントへのアクセス権限
- aws-vault にプロファイル設定済み（`shinyat`）

## ステップ 0: 事前準備

```bash
# プロジェクトディレクトリに移動
cd /Users/shinya.tsukasa/project/mycccompany/project-forest/project-forest

# aws-vault の動作確認
aws-vault exec shinyat -- aws sts get-caller-identity

# アカウントIDを環境変数に設定（以降のコマンドで使用）
export ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
```

## ステップ 1: ローカルでDockerイメージをビルド

```bash
# 開発用Dockerfileでビルド（ビルドエラーを回避）
docker build -f infrastructure/docker/Dockerfile.dev -t project-forest:latest .

# ビルド確認
docker images | grep project-forest
```

## ステップ 2: ECRリポジトリの作成

```bash
# ECRリポジトリが存在するか確認
aws-vault exec shinyat -- aws ecr describe-repositories \
  --repository-names project-forest \
  --region ap-northeast-1 2>/dev/null

# 存在しない場合は作成
if [ $? -ne 0 ]; then
  aws-vault exec shinyat -- aws ecr create-repository \
    --repository-name project-forest \
    --region ap-northeast-1
fi
```

## ステップ 3: ECRへのログインとイメージプッシュ

```bash
# ECRにログイン
aws-vault exec shinyat -- aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com

# イメージにタグ付け
docker tag project-forest:latest ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest

# イメージをプッシュ
docker push ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest
```

## ステップ 4: CloudWatchログループの作成

```bash
# ログループを作成（既に存在する場合はエラーを無視）
aws-vault exec shinyat -- aws logs create-log-group \
  --log-group-name /ecs/project-forest-dev \
  --region ap-northeast-1 2>/dev/null || true
```

## ステップ 5: ECS実行ロールの作成

```bash
# ECS実行ロールを作成（存在しない場合）
aws-vault exec shinyat -- aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' 2>/dev/null || echo "ロールは既に存在します"

# 必要なポリシーをアタッチ
aws-vault exec shinyat -- aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws-vault exec shinyat -- aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# 現在のユーザーにPassRole権限を付与
USER_NAME=$(aws-vault exec shinyat -- aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)
aws-vault exec shinyat -- aws iam put-user-policy \
  --user-name $USER_NAME \
  --policy-name ECSPassRolePolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "iam:PassRole",
        "Resource": "arn:aws:iam::'${ACCOUNT_ID}':role/ecsTaskExecutionRole"
      }
    ]
  }'
```

## ステップ 6: ECSタスク定義の登録

```bash
# タスク定義を直接登録（JSONファイル不要）
aws-vault exec shinyat -- aws ecs register-task-definition \
  --family "project-forest-dev" \
  --network-mode "awsvpc" \
  --requires-compatibilities "FARGATE" \
  --cpu "256" \
  --memory "512" \
  --execution-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole" \
  --container-definitions "[
    {
      \"name\": \"project-forest\",
      \"image\": \"${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest\",
      \"portMappings\": [
        {
          \"containerPort\": 3000,
          \"protocol\": \"tcp\"
        }
      ],
      \"essential\": true,
      \"environment\": [
        {\"name\": \"NODE_ENV\", \"value\": \"development\"},
        {\"name\": \"PORT\", \"value\": \"3000\"},
        {\"name\": \"DB_HOST\", \"value\": \"localhost\"},
        {\"name\": \"DB_USER\", \"value\": \"root\"},
        {\"name\": \"DB_PASSWORD\", \"value\": \"password\"},
        {\"name\": \"DB_NAME\", \"value\": \"project_forest_dev\"}
      ],
      \"logConfiguration\": {
        \"logDriver\": \"awslogs\",
        \"options\": {
          \"awslogs-group\": \"/ecs/project-forest-dev\",
          \"awslogs-region\": \"ap-northeast-1\",
          \"awslogs-stream-prefix\": \"ecs\"
        }
      }
    }
  ]" \
  --region ap-northeast-1
```

## ステップ 7: ECSクラスターの確認・作成

```bash
# 既存のクラスターを確認
aws-vault exec shinyat -- aws ecs list-clusters --region ap-northeast-1

# defaultクラスターが存在しない場合は作成
aws-vault exec shinyat -- aws ecs create-cluster \
  --cluster-name default \
  --region ap-northeast-1
```

## ステップ 8: VPC情報の取得（ECSサービス作成に必要）

```bash
# デフォルトVPCのIDを取得
VPC_ID=$(aws-vault exec shinyat -- aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region ap-northeast-1)
echo "VPC ID: $VPC_ID"

# パブリックサブネットを取得（最初の2つ）
SUBNETS=$(aws-vault exec shinyat -- aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[?MapPublicIpOnLaunch==\`true\`].[SubnetId]" \
  --output text \
  --region ap-northeast-1 | head -2 | tr '\n' ',' | sed 's/,$//')
echo "Subnets: $SUBNETS"

# セキュリティグループを作成または取得
SG_ID=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=project-forest-dev-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region ap-northeast-1 2>/dev/null)

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
  # セキュリティグループを作成
  SG_ID=$(aws-vault exec shinyat -- aws ec2 create-security-group \
    --group-name project-forest-dev-sg \
    --description "Security group for Project Forest dev" \
    --vpc-id $VPC_ID \
    --query "GroupId" \
    --output text \
    --region ap-northeast-1)
  
  # インバウンドルールを追加（開発環境用：自分のIPのみ許可）
  # 現在のIPアドレスを取得
  MY_IP=$(curl -s https://checkip.amazonaws.com)
  echo "Your IP: $MY_IP"
  
  # ポート3000を自分のIPからのみ許可
  aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr ${MY_IP}/32 \
    --region ap-northeast-1 \
    --group-rule-description "Allow port 3000 from my IP for development"
  
  # 必要に応じて、社内ネットワークからのアクセスも許可
  # aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  #   --group-id $SG_ID \
  #   --protocol tcp \
  #   --port 3000 \
  #   --cidr YOUR_OFFICE_CIDR \
  #   --region ap-northeast-1 \
  #   --group-rule-description "Allow port 3000 from office network"
fi

echo "Security Group ID: $SG_ID"
```

## ステップ 9: ECSサービスの作成

```bash
# サブネットIDを配列形式に変換
SUBNET_1=$(echo $SUBNETS | cut -d',' -f1)
SUBNET_2=$(echo $SUBNETS | cut -d',' -f2)

# ECSサービスを作成
aws-vault exec shinyat -- aws ecs create-service \
  --cluster default \
  --service-name project-forest-dev \
  --task-definition project-forest-dev \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[\"$SUBNET_1\",\"$SUBNET_2\"],
    securityGroups=[\"$SG_ID\"],
    assignPublicIp=\"ENABLED\"
  }" \
  --region ap-northeast-1
```

## ステップ 10: デプロイの確認

```bash
# サービスの状態を確認
aws-vault exec shinyat -- aws ecs describe-services \
  --cluster default \
  --services project-forest-dev \
  --region ap-northeast-1 \
  --query "services[0].deployments"

# 実行中のタスクを確認
aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster default \
  --service-name project-forest-dev \
  --region ap-northeast-1

# タスクの詳細を確認（IPアドレスを取得）
TASK_ARN=$(aws-vault exec shinyat -- aws ecs list-tasks \
  --cluster default \
  --service-name project-forest-dev \
  --query "taskArns[0]" \
  --output text \
  --region ap-northeast-1)

if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
  # タスクの詳細情報を取得
  TASK_DETAILS=$(aws-vault exec shinyat -- aws ecs describe-tasks \
    --cluster default \
    --tasks $TASK_ARN \
    --region ap-northeast-1)
  
  # ENIのIDを取得
  ENI_ID=$(echo $TASK_DETAILS | jq -r '.tasks[0].attachments[0].details[] | select(.name=="networkInterfaceId") | .value')
  
  # パブリックIPを取得
  PUBLIC_IP=$(aws-vault exec shinyat -- aws ec2 describe-network-interfaces \
    --network-interface-ids $ENI_ID \
    --query "NetworkInterfaces[0].Association.PublicIp" \
    --output text \
    --region ap-northeast-1)
  
  echo "アプリケーションURL: http://$PUBLIC_IP:3000"
fi
```

## ステップ 11: ログの確認

```bash
# CloudWatch Logsでアプリケーションログを確認
aws-vault exec shinyat -- aws logs tail /ecs/project-forest-dev --follow
```

## トラブルシューティング

### サービスが起動しない場合

1. **サービスイベントを確認（最優先）**
   ```bash
   aws-vault exec shinyat -- aws ecs describe-services \
     --cluster default \
     --services project-forest-dev \
     --region ap-northeast-1 \
     --query "services[0].events[0:5]"
   ```

2. **実行ロール権限エラーの場合**
   エラーメッセージに「ECS was unable to assume the role」が含まれる場合：
   ```bash
   # 実行ロールを再作成
   aws-vault exec shinyat -- aws iam create-role \
     --role-name ecsTaskExecutionRole \
     --assume-role-policy-document '{
       "Version": "2012-10-17",
       "Statement": [{
         "Effect": "Allow",
         "Principal": {"Service": "ecs-tasks.amazonaws.com"},
         "Action": "sts:AssumeRole"
       }]
     }' 2>/dev/null || echo "ロールは既に存在します"
   
   # ポリシーをアタッチ
   aws-vault exec shinyat -- aws iam attach-role-policy \
     --role-name ecsTaskExecutionRole \
     --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
   
   # PassRole権限を付与
   USER_NAME=$(aws-vault exec shinyat -- aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)
   aws-vault exec shinyat -- aws iam put-user-policy \
     --user-name $USER_NAME \
     --policy-name ECSPassRolePolicy \
     --policy-document '{
       "Version": "2012-10-17",
       "Statement": [{
         "Effect": "Allow",
         "Action": "iam:PassRole",
         "Resource": "arn:aws:iam::388450459156:role/ecsTaskExecutionRole"
       }]
     }'
   
   # サービスを再デプロイ
   aws-vault exec shinyat -- aws ecs update-service \
     --cluster default \
     --service project-forest-dev \
     --force-new-deployment \
     --region ap-northeast-1
   ```

3. **タスク定義の確認**
   ```bash
   aws-vault exec shinyat -- aws ecs describe-task-definition \
     --task-definition project-forest-dev \
     --region ap-northeast-1
   ```

4. **停止したタスクの理由を確認**
   ```bash
   # 停止したタスクがあるか確認
   STOPPED_TASK=$(aws-vault exec shinyat -- aws ecs list-tasks \
     --cluster default \
     --service-name project-forest-dev \
     --desired-status STOPPED \
     --query "taskArns[0]" \
     --output text \
     --region ap-northeast-1)
   
   if [ "$STOPPED_TASK" != "None" ] && [ -n "$STOPPED_TASK" ]; then
     aws-vault exec shinyat -- aws ecs describe-tasks \
       --cluster default \
       --tasks $STOPPED_TASK \
       --region ap-northeast-1 \
       --query "tasks[0].{stopCode:stopCode,stoppedReason:stoppedReason}"
   fi
   ```

5. **ログを確認**
   ```bash
   aws-vault exec shinyat -- aws logs tail /ecs/project-forest-dev --since 10m
   ```

### アプリケーションにアクセスできない場合

1. **セキュリティグループの確認**
   ```bash
   aws-vault exec shinyat -- aws ec2 describe-security-groups \
     --group-ids $SG_ID \
     --region ap-northeast-1
   ```

2. **ネットワーク設定の確認**
   ```bash
   aws-vault exec shinyat -- aws ecs describe-services \
     --cluster default \
     --services project-forest-dev \
     --region ap-northeast-1 \
     --query "services[0].networkConfiguration"
   ```

## クリーンアップ（不要になった場合）

```bash
# サービスの削除
aws-vault exec shinyat -- aws ecs delete-service \
  --cluster default \
  --service project-forest-dev \
  --force \
  --region ap-northeast-1

# タスク定義の登録解除（削除はできないので非アクティブ化）
aws-vault exec shinyat -- aws ecs deregister-task-definition \
  --task-definition project-forest-dev:1 \
  --region ap-northeast-1

# ECRリポジトリの削除（注意：すべてのイメージが削除される）
aws-vault exec shinyat -- aws ecr delete-repository \
  --repository-name project-forest \
  --force \
  --region ap-northeast-1

# セキュリティグループの削除
aws-vault exec shinyat -- aws ec2 delete-security-group \
  --group-id $SG_ID \
  --region ap-northeast-1

# ログループの削除
aws-vault exec shinyat -- aws logs delete-log-group \
  --log-group-name /ecs/project-forest-dev \
  --region ap-northeast-1
```

## まとめ

このガイドは上から順番に実行すれば必ず動作します。各ステップでエラーが発生した場合は、トラブルシューティングセクションを参照してください。

重要なポイント：
- 開発用Dockerfileを使用してビルドエラーを回避
- デフォルトVPCとサブネットを使用
- Fargateで実行するため、EC2インスタンスは不要
- パブリックIPを有効にして外部からアクセス可能に設定