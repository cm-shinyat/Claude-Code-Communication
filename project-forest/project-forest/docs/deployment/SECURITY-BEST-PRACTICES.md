# Project Forest セキュリティベストプラクティス

開発環境でもセキュリティを重視した設定を行うためのガイドです。

## 🔒 セキュリティグループの設定

### 問題点：全インターネットからのアクセス許可

Security Hubからのアラート：
```
EC2.18 Security groups should only allow unrestricted incoming traffic for authorized ports
```

**原因**: ポート3000を `0.0.0.0/0`（全インターネット）に開放していた

### 解決方法：IPアドレス制限

#### 1. 自分のIPアドレスのみ許可（推奨）

```bash
# 現在のIPアドレスを取得
MY_IP=$(curl -s https://checkip.amazonaws.com)

# セキュリティグループに自分のIPのみ許可
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr ${MY_IP}/32 \
  --region ap-northeast-1 \
  --group-rule-description "Allow port 3000 from my IP for development"
```

#### 2. 社内ネットワークからのアクセス許可

```bash
# 社内ネットワークのCIDRを指定
OFFICE_CIDR="203.0.113.0/24"  # 例：社内ネットワークのCIDR

aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr $OFFICE_CIDR \
  --region ap-northeast-1 \
  --group-rule-description "Allow port 3000 from office network"
```

#### 3. 複数のIPアドレスを許可する場合

```bash
# 許可するIPアドレスのリスト
ALLOWED_IPS=(
  "203.0.113.1/32"    # 開発者A
  "203.0.113.2/32"    # 開発者B
  "198.51.100.0/24"   # オフィスネットワーク
)

# 各IPアドレスに対してルールを追加
for IP in "${ALLOWED_IPS[@]}"; do
  aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr $IP \
    --region ap-northeast-1 \
    --group-rule-description "Allow port 3000 from authorized IP: $IP"
done
```

## 🛡️ その他のセキュリティ設定

### 1. Application Load Balancer (ALB) の使用

開発環境でもALBを使用することで、セキュリティを向上できます：

```bash
# ALBを作成し、セキュリティグループはALBのみに適用
# ECSタスクへの直接アクセスを防ぐ
```

### 2. VPN接続の使用

AWS Client VPNを使用して、安全な接続を確立：

```bash
# VPNエンドポイントを作成
# 開発者はVPN経由でのみアクセス可能
```

### 3. Systems Manager Session Manager

EC2インスタンスへのSSH接続の代わりに使用：

```bash
# Session Manager経由でコンテナにアクセス
aws-vault exec shinyat -- aws ecs execute-command \
  --cluster default \
  --task $TASK_ARN \
  --container project-forest \
  --interactive \
  --command "/bin/sh"
```

## 📋 セキュリティチェックリスト

### デプロイ前の確認事項

- [ ] セキュリティグループは特定のIPアドレスのみ許可
- [ ] 不要なポートは開放していない
- [ ] IAMロールは最小権限の原則に従っている
- [ ] 環境変数にシークレット情報を含めていない
- [ ] CloudWatchログに機密情報が記録されないよう設定

### デプロイ後の確認事項

- [ ] Security Hubでアラートが出ていないか確認
- [ ] セキュリティグループの設定を再確認
- [ ] 不正なアクセスログがないか確認

## 🚨 セキュリティグループの確認と修正

### 現在の設定を確認

```bash
# セキュリティグループの詳細を確認
aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region ap-northeast-1 \
  --query "SecurityGroups[0].IpPermissions"
```

### 不適切なルールを削除

```bash
# 0.0.0.0/0 からのアクセスを削除
aws-vault exec shinyat -- aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-1
```

### 適切なルールを追加

```bash
# 自分のIPのみ許可
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr ${MY_IP}/32 \
  --region ap-northeast-1 \
  --group-rule-description "Allow port 3000 from my IP only"
```

## 🔄 IPアドレスが変わった場合の更新方法

IPアドレスが変わった場合（自宅のIPが動的な場合など）の更新スクリプト：

```bash
#!/bin/bash
# update-security-group.sh

SG_ID="sg-xxxxx"  # あなたのセキュリティグループID
REGION="ap-northeast-1"

# 現在のIPを取得
NEW_IP=$(curl -s https://checkip.amazonaws.com)
echo "New IP: $NEW_IP"

# 古いルールを取得
OLD_RULES=$(aws-vault exec shinyat -- aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissions[?ToPort==\`3000\`].IpRanges[].CidrIp" \
  --output text)

# 古いルールを削除
for OLD_IP in $OLD_RULES; do
  echo "Removing old rule: $OLD_IP"
  aws-vault exec shinyat -- aws ec2 revoke-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr $OLD_IP \
    --region $REGION
done

# 新しいルールを追加
echo "Adding new rule: ${NEW_IP}/32"
aws-vault exec shinyat -- aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr ${NEW_IP}/32 \
  --region $REGION \
  --group-rule-description "Allow port 3000 from my current IP"

echo "Security group updated successfully!"
```

## 📚 参考リンク

- [AWS Security Hub - EC2.18](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp-controls.html#fsbp-ec2-18)
- [セキュリティグループのベストプラクティス](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html)
- [最小権限の原則](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege)

## まとめ

開発環境でも本番環境と同様のセキュリティ意識を持つことが重要です。特に：

1. **最小権限の原則**: 必要最小限のアクセスのみ許可
2. **IPアドレス制限**: 0.0.0.0/0は使用しない
3. **定期的な監査**: Security Hubのアラートを確認
4. **ログの監視**: 不正アクセスの兆候を確認

これらの設定により、Security Hubのアラートを回避し、より安全な開発環境を構築できます。