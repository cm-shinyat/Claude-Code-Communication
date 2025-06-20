# Project Forest - AWS デプロイメント手順書

## 概要

本ドキュメントは、Project Forest（テキスト管理システム）をAWSにデプロイするための詳細な手順書です。初回セットアップから本番運用まで、技術者が迷わず実行できるよう段階的に説明します。

## 前提条件

### 必要なツール

- AWS CLI (v2.0以上)
- Node.js (v18.0以上)
- npm または yarn
- Git
- MySQL クライアント

### 必要な権限

- AWSアカウントの管理者権限またはEC2、RDS、S3、CloudFront、Route53の操作権限
- ドメインの管理権限（独自ドメインを使用する場合）

### システム要件

- **EC2インスタンス**: t3.medium以上（本番環境ではt3.large推奨）
- **RDS**: db.t3.micro以上（本番環境ではdb.t3.small推奨）
- **ストレージ**: 最低20GB（ログとファイルアップロード用）

## Phase 1: AWS CLI設定

### 1.1 AWS CLIのセットアップ

```bash
# AWS CLIのインストール確認
aws --version

# AWSアカウントの設定
aws configure
```

設定項目：
- **AWS Access Key ID**: IAMユーザーのアクセスキー
- **AWS Secret Access Key**: IAMユーザーのシークレットキー
- **Default region name**: `ap-northeast-1` (東京リージョン)
- **Default output format**: `json`

### 1.2 IAMロールの設定

```bash
# EC2用IAMロールの作成
aws iam create-role --role-name ProjectForestEC2Role --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# 必要なポリシーをアタッチ
aws iam attach-role-policy --role-name ProjectForestEC2Role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name ProjectForestEC2Role --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# インスタンスプロファイルの作成
aws iam create-instance-profile --instance-profile-name ProjectForestEC2Profile
aws iam add-role-to-instance-profile --instance-profile-name ProjectForestEC2Profile --role-name ProjectForestEC2Role
```

## Phase 2: ネットワーク環境構築

### 2.1 VPCとサブネットの作成

```bash
# VPCの作成
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ProjectForestVPC}]' --query 'Vpc.VpcId' --output text)
echo "VPC ID: $VPC_ID"

# インターネットゲートウェイの作成とアタッチ
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=ProjectForestIGW}]' --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# パブリックサブネットの作成 (AZ: ap-northeast-1a)
PUBLIC_SUBNET_1A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ap-northeast-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=ProjectForestPublicSubnet1A}]' --query 'Subnet.SubnetId' --output text)

# パブリックサブネットの作成 (AZ: ap-northeast-1c)
PUBLIC_SUBNET_1C=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ap-northeast-1c --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=ProjectForestPublicSubnet1C}]' --query 'Subnet.SubnetId' --output text)

# プライベートサブネットの作成 (AZ: ap-northeast-1a)
PRIVATE_SUBNET_1A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.11.0/24 --availability-zone ap-northeast-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=ProjectForestPrivateSubnet1A}]' --query 'Subnet.SubnetId' --output text)

# プライベートサブネットの作成 (AZ: ap-northeast-1c)
PRIVATE_SUBNET_1C=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.12.0/24 --availability-zone ap-northeast-1c --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=ProjectForestPrivateSubnet1C}]' --query 'Subnet.SubnetId' --output text)

echo "Public Subnet 1A: $PUBLIC_SUBNET_1A"
echo "Public Subnet 1C: $PUBLIC_SUBNET_1C"
echo "Private Subnet 1A: $PRIVATE_SUBNET_1A"
echo "Private Subnet 1C: $PRIVATE_SUBNET_1C"
```

### 2.2 ルートテーブルの設定

```bash
# パブリックサブネット用ルートテーブルの作成
PUBLIC_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=ProjectForestPublicRT}]' --query 'RouteTable.RouteTableId' --output text)

# インターネットゲートウェイへのルートを追加
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# サブネットとルートテーブルの関連付け
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1A --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1C --route-table-id $PUBLIC_RT_ID

# パブリックIPの自動割り当てを有効化
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1A --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1C --map-public-ip-on-launch
```

### 2.3 セキュリティグループの作成

```bash
# Webサーバー用セキュリティグループ
WEB_SG_ID=$(aws ec2 create-security-group --group-name ProjectForestWebSG --description "Security group for Project Forest web servers" --vpc-id $VPC_ID --query 'GroupId' --output text)

# HTTP/HTTPSアクセスを許可
aws ec2 authorize-security-group-ingress --group-id $WEB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $WEB_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $WEB_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

# データベース用セキュリティグループ
DB_SG_ID=$(aws ec2 create-security-group --group-name ProjectForestDBSG --description "Security group for Project Forest database" --vpc-id $VPC_ID --query 'GroupId' --output text)

# Webサーバーからのデータベースアクセスを許可
aws ec2 authorize-security-group-ingress --group-id $DB_SG_ID --protocol tcp --port 3306 --source-group $WEB_SG_ID

echo "Web Security Group: $WEB_SG_ID"
echo "DB Security Group: $DB_SG_ID"
```

## Phase 3: データベース環境構築

### 3.1 RDS サブネットグループの作成

```bash
# DBサブネットグループの作成
aws rds create-db-subnet-group \
  --db-subnet-group-name projectforest-db-subnet-group \
  --db-subnet-group-description "Subnet group for Project Forest database" \
  --subnet-ids $PRIVATE_SUBNET_1A $PRIVATE_SUBNET_1C \
  --tags Key=Name,Value=ProjectForestDBSubnetGroup
```

### 3.2 RDS インスタンスの作成

```bash
# データベースの作成
aws rds create-db-instance \
  --db-instance-identifier projectforest-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username admin \
  --master-user-password 'ProjectForest2024!' \
  --allocated-storage 20 \
  --vpc-security-group-ids $DB_SG_ID \
  --db-subnet-group-name projectforest-db-subnet-group \
  --backup-retention-period 7 \
  --storage-encrypted \
  --monitoring-interval 60 \
  --monitoring-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/rds-monitoring-role \
  --deletion-protection \
  --tags Key=Name,Value=ProjectForestDB Key=Environment,Value=production
```

### 3.3 データベース接続の確認

```bash
# RDSエンドポイントの取得
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier projectforest-db --query 'DBInstances[0].Endpoint.Address' --output text)
echo "Database Endpoint: $DB_ENDPOINT"

# データベースが利用可能になるまで待機
aws rds wait db-instance-available --db-instance-identifier projectforest-db
```

## Phase 4: アプリケーションサーバー構築

### 4.1 キーペアの作成

```bash
# EC2キーペアの作成
aws ec2 create-key-pair --key-name ProjectForestKey --query 'KeyMaterial' --output text > ~/.ssh/ProjectForestKey.pem
chmod 400 ~/.ssh/ProjectForestKey.pem
```

### 4.2 EC2インスタンスの起動

```bash
# 最新のAmazon Linux 2 AMI IDを取得
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text)

# EC2インスタンスの起動
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.medium \
  --key-name ProjectForestKey \
  --security-group-ids $WEB_SG_ID \
  --subnet-id $PUBLIC_SUBNET_1A \
  --iam-instance-profile Name=ProjectForestEC2Profile \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ProjectForestWebServer}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance ID: $INSTANCE_ID"

# インスタンスが起動するまで待機
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# パブリックIPアドレスの取得
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Public IP: $PUBLIC_IP"
```

### 4.3 ユーザーデータスクリプトの作成

```bash
# user-data.shファイルの作成
cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y

# Node.js 18のインストール
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Nginxのインストール
amazon-linux-extras install nginx1 -y

# PM2のインストール
npm install -g pm2

# MySQLクライアントのインストール
yum install -y mysql

# アプリケーション用ディレクトリの作成
mkdir -p /var/www/project-forest
chown ec2-user:ec2-user /var/www/project-forest

# ログディレクトリの作成
mkdir -p /var/log/project-forest
chown ec2-user:ec2-user /var/log/project-forest

# Nginxの起動
systemctl start nginx
systemctl enable nginx

# CloudWatch Logsエージェントのインストールと設定
yum install -y awslogs
systemctl start awslogsd
systemctl enable awslogsd
EOF
```

## Phase 5: S3とCloudFrontの設定

### 5.1 S3バケットの作成

```bash
# 静的ファイル用S3バケットの作成
BUCKET_NAME="projectforest-static-$(date +%s)"
aws s3 mb s3://$BUCKET_NAME --region ap-northeast-1

# バケットポリシーの設定
cat > bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://bucket-policy.json

# バケットのWebサイト設定
aws s3 website s3://$BUCKET_NAME --index-document index.html --error-document error.html

echo "S3 Bucket: $BUCKET_NAME"
```

### 5.2 CloudFrontディストリビューションの作成

```bash
# CloudFrontディストリビューション設定
cat > cloudfront-config.json << EOF
{
  "CallerReference": "project-forest-$(date +%s)",
  "Comment": "Project Forest CDN",
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-$BUCKET_NAME",
    "ViewerProtocolPolicy": "redirect-to-https",
    "TrustedSigners": {
      "Enabled": false,
      "Quantity": 0
    },
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {
        "Forward": "none"
      }
    },
    "MinTTL": 0,
    "Compress": true
  },
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-$BUCKET_NAME",
        "DomainName": "$BUCKET_NAME.s3.amazonaws.com",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "Enabled": true,
  "PriceClass": "PriceClass_All"
}
EOF

# CloudFrontディストリビューションの作成
DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config file://cloudfront-config.json --query 'Distribution.Id' --output text)
echo "CloudFront Distribution ID: $DISTRIBUTION_ID"
```

## Phase 6: アプリケーションのデプロイ

### 6.1 アプリケーションのビルドとアップロード

```bash
# ローカルでのビルド
npm run build

# アプリケーションファイルをEC2にアップロード
scp -i ~/.ssh/ProjectForestKey.pem -r ./* ec2-user@$PUBLIC_IP:/var/www/project-forest/

# EC2インスタンスにSSH接続
ssh -i ~/.ssh/ProjectForestKey.pem ec2-user@$PUBLIC_IP
```

### 6.2 EC2インスタンス内でのセットアップ

EC2インスタンス内で実行：

```bash
cd /var/www/project-forest

# 依存関係のインストール
npm install --production

# 環境変数の設定
cat > .env.production << EOF
NODE_ENV=production
PORT=3000
DATABASE_URL=mysql://admin:ProjectForest2024!@$DB_ENDPOINT:3306/projectforest
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NEXTAUTH_URL=https://your-domain.com
AWS_REGION=ap-northeast-1
S3_BUCKET_NAME=$BUCKET_NAME
EOF

# データベースの初期化
mysql -h $DB_ENDPOINT -u admin -p'ProjectForest2024!' << 'EOF'
CREATE DATABASE IF NOT EXISTS projectforest;
USE projectforest;
source database/schema.sql;
EOF

# PM2でアプリケーションを起動
pm2 start npm --name "project-forest" -- start
pm2 startup
pm2 save
```

### 6.3 Nginxの設定

```bash
# Nginx設定ファイルの作成
sudo tee /etc/nginx/conf.d/project-forest.conf << 'EOF'
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Nginxの再起動
sudo systemctl restart nginx
```

## Phase 7: SSL証明書の設定

### 7.1 Route53での独自ドメイン設定

```bash
# ホストゾーンの作成（独自ドメインを使用する場合）
HOSTED_ZONE_ID=$(aws route53 create-hosted-zone --name your-domain.com --caller-reference $(date +%s) --query 'HostedZone.Id' --output text)

# Aレコードの作成
cat > change-batch.json << EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "your-domain.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "$PUBLIC_IP"
          }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file://change-batch.json
```

### 7.2 Let's Encryptを使用したSSL証明書の設定

EC2インスタンス内で実行：

```bash
# Certbotのインストール
sudo yum install -y certbot python3-certbot-nginx

# SSL証明書の取得
sudo certbot --nginx -d your-domain.com -d www.your-domain.com --email your-email@example.com --agree-tos --non-interactive

# 自動更新の設定
echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
```

## Phase 8: モニタリングとログ設定

### 8.1 CloudWatch Logsの設定

```bash
# CloudWatch Logs設定ファイルの作成
sudo tee /etc/awslogs/awslogs.conf << 'EOF'
[general]
state_file = /var/lib/awslogs/agent-state

[/var/log/project-forest/app.log]
file = /var/log/project-forest/app.log
log_group_name = /aws/ec2/project-forest/app
log_stream_name = {instance_id}
datetime_format = %Y-%m-%d %H:%M:%S

[/var/log/nginx/access.log]
file = /var/log/nginx/access.log
log_group_name = /aws/ec2/project-forest/nginx-access
log_stream_name = {instance_id}
datetime_format = %d/%b/%Y:%H:%M:%S %z

[/var/log/nginx/error.log]
file = /var/log/nginx/error.log
log_group_name = /aws/ec2/project-forest/nginx-error
log_stream_name = {instance_id}
datetime_format = %Y/%m/%d %H:%M:%S
EOF

# CloudWatch Logsエージェントの再起動
sudo systemctl restart awslogsd
```

### 8.2 CloudWatchアラームの設定

```bash
# CPU使用率アラーム
aws cloudwatch put-metric-alarm \
  --alarm-name "ProjectForest-HighCPU" \
  --alarm-description "Project Forest high CPU utilization" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --evaluation-periods 2

# メモリ使用率アラーム
aws cloudwatch put-metric-alarm \
  --alarm-name "ProjectForest-HighMemory" \
  --alarm-description "Project Forest high memory utilization" \
  --metric-name MemoryUtilization \
  --namespace CWAgent \
  --statistic Average \
  --period 300 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --evaluation-periods 2
```

## Phase 9: バックアップ設定

### 9.1 RDSの自動バックアップ設定

```bash
# バックアップ設定の確認・更新
aws rds modify-db-instance \
  --db-instance-identifier projectforest-db \
  --backup-retention-period 30 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "Sun:04:00-Sun:05:00" \
  --apply-immediately
```

### 9.2 EBSスナップショットの自動化

```bash
# Lambda関数用のIAMロールの作成
aws iam create-role --role-name EBSSnapshotRole --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# 必要なポリシーをアタッチ
aws iam attach-role-policy --role-name EBSSnapshotRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam attach-role-policy --role-name EBSSnapshotRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

## Phase 10: デプロイメント検証

### 10.1 アプリケーションの動作確認

```bash
# ヘルスチェックエンドポイントの確認
curl -f http://your-domain.com/api/health

# データベース接続の確認
curl -f http://your-domain.com/api/db-status

# 管理画面アクセスの確認
curl -f http://your-domain.com/admin
```

### 10.2 パフォーマンステスト

```bash
# ApacheBench による負荷テスト（オプション）
ab -n 1000 -c 10 http://your-domain.com/

# レスポンス時間の確認
curl -w "@curl-format.txt" -o /dev/null -s http://your-domain.com/
```

curl-format.txtファイル：
```
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
```

## 設定値の保存

重要な設定値を記録してください：

```bash
echo "=== Project Forest AWS Configuration ==="
echo "VPC ID: $VPC_ID"
echo "Public Subnet 1A: $PUBLIC_SUBNET_1A"
echo "Public Subnet 1C: $PUBLIC_SUBNET_1C"
echo "Private Subnet 1A: $PRIVATE_SUBNET_1A"
echo "Private Subnet 1C: $PRIVATE_SUBNET_1C"
echo "Web Security Group: $WEB_SG_ID"
echo "DB Security Group: $DB_SG_ID"
echo "Database Endpoint: $DB_ENDPOINT"
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "S3 Bucket: $BUCKET_NAME"
echo "CloudFront Distribution ID: $DISTRIBUTION_ID"
echo "============================================"
```

これらの値は今後の運用・保守で必要になるため、安全な場所に保管してください。

## 次のステップ

1. [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) - インフラストラクチャの詳細設定
2. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - トラブルシューティングガイド

## セキュリティ推奨事項

- 定期的なパスワード変更
- MFA（多要素認証）の有効化
- 不要なポートの閉鎖
- 定期的なセキュリティアップデート
- アクセスログの監視

本デプロイメント手順書に従って作業を進めることで、Project ForestをAWS上で安全かつ効率的に運用することができます。