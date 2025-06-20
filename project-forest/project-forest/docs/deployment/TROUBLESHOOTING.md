# Project Forest - トラブルシューティングガイド

## 概要

本ドキュメントは、Project Forest（テキスト管理システム）のAWS環境で発生する可能性のある問題と、その解決方法を体系的にまとめたトラブルシューティングガイドです。

## 緊急時対応フロー

### 1. 重大障害発生時の対応手順

#### 1.1 初期対応（最初の5分）

```bash
# システム全体の状況確認
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
aws rds describe-db-instances --db-instance-identifier projectforest-db
aws ec2 describe-instance-status --instance-ids <INSTANCE_IDS>

# CloudWatchでアラーム状況確認
aws cloudwatch describe-alarms --state-value ALARM
```

#### 1.2 詳細調査（5-15分）

```bash
# アプリケーションログの確認
aws logs filter-log-events --log-group-name /aws/ec2/project-forest/app --start-time $(date -d '1 hour ago' +%s)000

# システムメトリクスの確認
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --start-time $(date -d '1 hour ago' --iso-8601) --end-time $(date --iso-8601) --period 300 --statistics Average
```

#### 1.3 復旧作業（15分以降）

問題に応じて本ガイドの該当セクションを参照

## アプリケーション関連の問題

### A-1. アプリケーション起動エラー

#### 症状
- ヘルスチェックが失敗する
- 500 Internal Server Error が発生
- PM2プロセスが停止している

#### 確認方法

```bash
# EC2インスタンスにSSH接続
ssh -i ~/.ssh/ProjectForestKey.pem ec2-user@<PUBLIC_IP>

# PM2プロセス状況確認
pm2 list

# アプリケーションログ確認
pm2 logs project-forest

# Next.jsのビルド状況確認
cd /var/www/project-forest
npm run build
```

#### 解決方法

```bash
# 1. 環境変数の確認
cat .env.production

# 2. 依存関係の再インストール
npm install --production

# 3. PM2プロセスの再起動
pm2 restart project-forest

# 4. 完全な再起動が必要な場合
pm2 delete project-forest
pm2 start npm --name "project-forest" -- start

# 5. ログ監視
pm2 logs project-forest --lines 100
```

#### よくある原因と対策

| 原因 | 症状 | 対策 |
|------|------|------|
| 環境変数未設定 | DB接続エラー | `.env.production`の確認・修正 |
| ポート競合 | 起動失敗 | `lsof -i :3000`でポート確認 |
| メモリ不足 | OOM Killer | インスタンスサイズアップ |
| 依存関係エラー | モジュール未発見 | `npm install`の再実行 |

### A-2. データベース接続エラー

#### 症状
- "Connection refused" エラー
- タイムアウトエラー
- 認証エラー

#### 確認方法

```bash
# データベース接続テスト
mysql -h <DB_ENDPOINT> -u admin -p

# セキュリティグループ確認
aws ec2 describe-security-groups --group-ids <DB_SECURITY_GROUP_ID>

# RDS状況確認
aws rds describe-db-instances --db-instance-identifier projectforest-db
```

#### 解決方法

```bash
# 1. RDSインスタンス状況確認
aws rds describe-db-instances --db-instance-identifier projectforest-db --query 'DBInstances[0].DBInstanceStatus'

# 2. セキュリティグループルール確認
aws ec2 describe-security-groups --group-ids <DB_SG_ID> --query 'SecurityGroups[0].IpPermissions'

# 3. 接続文字列の確認
echo $DATABASE_URL

# 4. データベース接続プールの設定確認（アプリケーション内）
# prisma/schema.prisma または データベース設定ファイルを確認
```

#### RDS特有の問題

| エラー | 原因 | 対策 |
|-------|------|------|
| Too many connections | 接続数上限 | 接続プール設定見直し |
| Access denied | 認証情報誤り | パスワード・ユーザー名確認 |
| Unknown database | DB未作成 | データベース作成 |
| Connection timeout | ネットワーク問題 | セキュリティグループ確認 |

### A-3. パフォーマンス問題

#### 症状
- ページ読み込みが遅い
- タイムアウト頻発
- CPU使用率が高い

#### 確認方法

```bash
# システムリソース確認
top
htop
iostat -x 1

# データベースパフォーマンス確認
aws rds describe-db-instances --db-instance-identifier projectforest-db --query 'DBInstances[0].DbInstanceStatus'

# CloudWatchメトリクス確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --start-time $(date -d '1 hour ago' --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 300 \
  --statistics Average,Maximum
```

#### 解決方法

```bash
# 1. Next.jsアプリケーションの最適化
npm run build -- --debug

# 2. データベースクエリの最適化
# スロークエリログの確認
mysql -h <DB_ENDPOINT> -u admin -p -e "SET GLOBAL slow_query_log = 'ON';"
mysql -h <DB_ENDPOINT> -u admin -p -e "SET GLOBAL long_query_time = 2;"

# 3. キャッシュの有効化確認
redis-cli -h <ELASTICACHE_ENDPOINT> ping

# 4. Auto Scalingトリガー確認
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names projectforest-asg
```

## インフラストラクチャ関連の問題

### I-1. EC2インスタンス関連

#### I-1.1 インスタンス起動失敗

```bash
# インスタンス状況確認
aws ec2 describe-instances --instance-ids <INSTANCE_ID>

# システムログ確認
aws ec2 get-console-output --instance-id <INSTANCE_ID>

# インスタンス状態変更履歴
aws ec2 describe-instance-status --instance-ids <INSTANCE_ID> --include-all-instances
```

#### よくある起動失敗の原因

| 原因 | 対策 |
|------|------|
| セキュリティグループ設定ミス | ルール確認・修正 |
| サブネット容量不足 | 別サブネット利用 |
| IAMロール権限不足 | ポリシー確認・修正 |
| AMI利用不可 | 別AMI選択 |
| キーペア未指定 | キーペア設定 |

#### I-1.2 SSH接続できない

```bash
# セキュリティグループ確認
aws ec2 describe-security-groups --group-ids <SG_ID>

# キーペア確認
ssh-keygen -l -f ~/.ssh/ProjectForestKey.pem

# 接続テスト（詳細モード）
ssh -v -i ~/.ssh/ProjectForestKey.pem ec2-user@<PUBLIC_IP>
```

#### 解決方法

```bash
# 1. セキュリティグループにSSHルール追加
aws ec2 authorize-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp \
  --port 22 \
  --cidr <YOUR_IP>/32

# 2. キーペア権限確認
chmod 400 ~/.ssh/ProjectForestKey.pem

# 3. 踏み台サーバー経由でのアクセス
ssh -i ~/.ssh/ProjectForestKey.pem -J ec2-user@<BASTION_IP> ec2-user@<PRIVATE_IP>
```

### I-2. Load Balancer関連

#### I-2.1 ALBヘルスチェック失敗

```bash
# ターゲットグループ状況確認
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>

# ALBアクセスログ確認
aws s3 ls s3://<ALB_LOG_BUCKET>/ --recursive
aws s3 cp s3://<ALB_LOG_BUCKET>/<LOG_FILE> - | grep "target_status_code"
```

#### 解決方法

```bash
# 1. ヘルスチェックパス確認
curl -f http://<INSTANCE_PRIVATE_IP>:3000/api/health

# 2. セキュリティグループ設定確認
aws ec2 describe-security-groups --group-ids <WEB_SG_ID>

# 3. アプリケーション起動状況確認
ssh -i ~/.ssh/ProjectForestKey.pem ec2-user@<IP>
pm2 list
pm2 logs project-forest
```

#### I-2.2 504 Gateway Timeout

```bash
# タイムアウト設定確認
aws elbv2 describe-target-groups --target-group-arns <TARGET_GROUP_ARN> --query 'TargetGroups[0].HealthCheckTimeoutSeconds'

# アプリケーション応答時間確認
curl -w "@curl-format.txt" -o /dev/null -s http://<INSTANCE_IP>:3000/api/health
```

### I-3. データベース関連

#### I-3.1 RDS接続数上限エラー

```bash
# 現在の接続数確認
mysql -h <DB_ENDPOINT> -u admin -p -e "SHOW PROCESSLIST;"
mysql -h <DB_ENDPOINT> -u admin -p -e "SHOW STATUS LIKE 'Threads_connected';"

# 最大接続数確認
mysql -h <DB_ENDPOINT> -u admin -p -e "SHOW VARIABLES LIKE 'max_connections';"
```

#### 解決方法

```bash
# 1. 接続プール設定確認・調整
# アプリケーションのデータベース設定を確認

# 2. 不要な接続終了
mysql -h <DB_ENDPOINT> -u admin -p -e "KILL <PROCESS_ID>;"

# 3. RDSインスタンスクラスアップグレード
aws rds modify-db-instance \
  --db-instance-identifier projectforest-db \
  --db-instance-class db.t3.medium \
  --apply-immediately
```

#### I-3.2 RDSフェイルオーバー

```bash
# フェイルオーバー実行
aws rds reboot-db-instance \
  --db-instance-identifier projectforest-db \
  --force-failover

# フェイルオーバー後の状況確認
aws rds describe-db-instances --db-instance-identifier projectforest-db \
  --query 'DBInstances[0].[AvailabilityZone,SecondaryAvailabilityZone,MultiAZ]'
```

### I-4. ネットワーク関連

#### I-4.1 NAT Gateway問題

```bash
# NAT Gateway状況確認
aws ec2 describe-nat-gateways --filter "Name=state,Values=available"

# ルートテーブル確認
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=<PRIVATE_SUBNET_ID>"
```

#### I-4.2 DNS解決問題

```bash
# DNS設定確認
nslookup <DOMAIN_NAME>
dig <DOMAIN_NAME>

# Route53レコード確認
aws route53 list-resource-record-sets --hosted-zone-id <HOSTED_ZONE_ID>
```

## セキュリティ関連の問題

### S-1. WAF関連

#### S-1.1 正当なトラフィックがブロックされる

```bash
# WAFログ確認
aws wafv2 get-sampled-requests \
  --web-acl-arn <WEB_ACL_ARN> \
  --rule-metric-name <RULE_NAME> \
  --scope CLOUDFRONT \
  --time-window StartTime=$(date -d '1 hour ago' +%s),EndTime=$(date +%s) \
  --max-items 100
```

#### 解決方法

```bash
# 1. IPアドレスをホワイトリストに追加
aws wafv2 update-ip-set \
  --scope CLOUDFRONT \
  --id <IP_SET_ID> \
  --addresses <IP_ADDRESS>/32

# 2. レート制限の緩和
aws wafv2 update-rule-group \
  --scope CLOUDFRONT \
  --id <RULE_GROUP_ID> \
  --rules file://updated-rules.json
```

### S-2. SSL証明書関連

#### S-2.1 SSL証明書期限切れ

```bash
# 証明書状況確認
aws acm list-certificates --certificate-statuses ISSUED
aws acm describe-certificate --certificate-arn <CERTIFICATE_ARN>

# Let's Encrypt更新確認
sudo certbot certificates
sudo certbot renew --dry-run
```

#### 解決方法

```bash
# 1. Let's Encrypt証明書の手動更新
sudo certbot renew

# 2. ACM証明書の再作成
aws acm request-certificate \
  --domain-name <DOMAIN_NAME> \
  --validation-method DNS \
  --subject-alternative-names www.<DOMAIN_NAME>
```

## 監視・ログ関連の問題

### M-1. CloudWatch Logs

#### M-1.1 ログが送信されない

```bash
# CloudWatch Logsエージェント状況確認
sudo systemctl status awslogsd

# 設定ファイル確認
sudo cat /etc/awslogs/awslogs.conf

# エージェントログ確認
sudo tail -f /var/log/awslogs.log
```

#### 解決方法

```bash
# 1. エージェント再起動
sudo systemctl restart awslogsd

# 2. 設定ファイル修正
sudo vi /etc/awslogs/awslogs.conf

# 3. IAMロール権限確認
aws iam get-role-policy --role-name ProjectForestEC2Role --policy-name CloudWatchLogsPolicy
```

### M-2. CloudWatchメトリクス

#### M-2.1 カスタムメトリクスが表示されない

```bash
# メトリクス送信テスト
aws cloudwatch put-metric-data \
  --namespace "Project Forest" \
  --metric-data MetricName=TestMetric,Value=1.0

# メトリクス確認
aws cloudwatch list-metrics --namespace "Project Forest"
```

## パフォーマンス最適化

### P-1. データベース最適化

#### P-1.1 スロークエリ最適化

```sql
-- スロークエリログ有効化
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- インデックス確認
SHOW INDEX FROM text_entries;
SHOW INDEX FROM translations;

-- 実行計画確認
EXPLAIN SELECT * FROM text_entries WHERE status = '未処理' LIMIT 20;
```

#### P-1.2 インデックス追加

```sql
-- よく使用される検索条件にインデックス追加
CREATE INDEX idx_text_entries_status ON text_entries(status);
CREATE INDEX idx_text_entries_updated_at ON text_entries(updated_at);
CREATE INDEX idx_translations_language_code ON translations(language_code);
CREATE INDEX idx_translations_status ON translations(status);
```

### P-2. アプリケーション最適化

#### P-2.1 Next.js最適化

```bash
# バンドルサイズ分析
npm run build -- --analyze

# 画像最適化確認
npm install next-optimized-images

# キャッシュ設定確認
curl -I https://<DOMAIN>/api/health
```

#### P-2.2 Redis キャッシュ最適化

```bash
# Redis接続確認
redis-cli -h <ELASTICACHE_ENDPOINT> ping

# キャッシュ統計確認
redis-cli -h <ELASTICACHE_ENDPOINT> info stats

# キャッシュ設定最適化
redis-cli -h <ELASTICACHE_ENDPOINT> config get maxmemory-policy
```

## 災害復旧手順

### DR-1. データベース復旧

#### DR-1.1 ポイントインタイムリカバリ

```bash
# 復旧用RDSインスタンス作成
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier projectforest-db \
  --target-db-instance-identifier projectforest-db-restore \
  --restore-time 2024-01-01T12:00:00.000Z

# 復旧状況確認
aws rds describe-db-instances --db-instance-identifier projectforest-db-restore
```

#### DR-1.2 スナップショットからの復旧

```bash
# 利用可能なスナップショット確認
aws rds describe-db-snapshots --db-instance-identifier projectforest-db

# スナップショットから復旧
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier projectforest-db-restore \
  --db-snapshot-identifier <SNAPSHOT_ID>
```

### DR-2. アプリケーション復旧

#### DR-2.1 Auto Scaling Group復旧

```bash
# 新しいLaunch Template作成
aws ec2 create-launch-template \
  --launch-template-name ProjectForestTemplate-v2 \
  --launch-template-data file://launch-template.json

# Auto Scaling Group更新
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name projectforest-asg \
  --launch-template LaunchTemplateName=ProjectForestTemplate-v2,Version='$Latest' \
  --min-size 2 \
  --max-size 6 \
  --desired-capacity 2
```

## 予防保守

### 定期点検項目

#### 日次点検

```bash
#!/bin/bash
# daily-check.sh

echo "=== Project Forest Daily Health Check ==="
echo "Date: $(date)"

# システム稼働状況
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>

# データベース状況
aws rds describe-db-instances --db-instance-identifier projectforest-db --query 'DBInstances[0].DBInstanceStatus'

# ディスク使用量
df -h | grep -E "(/$|/var)"

# プロセス状況
pm2 list

echo "=== Check completed ==="
```

#### 週次点検

```bash
#!/bin/bash
# weekly-check.sh

echo "=== Project Forest Weekly Maintenance ==="

# バックアップ状況確認
aws rds describe-db-snapshots --db-instance-identifier projectforest-db --max-items 5

# CloudWatchアラーム状況
aws cloudwatch describe-alarms --state-value ALARM

# セキュリティパッチ確認
sudo yum check-update

# ログローテーション確認
sudo logrotate -d /etc/logrotate.conf

echo "=== Weekly maintenance completed ==="
```

#### 月次点検

```bash
#!/bin/bash
# monthly-check.sh

echo "=== Project Forest Monthly Review ==="

# コスト確認
aws ce get-cost-and-usage \
  --time-period Start=$(date -d 'last month' +%Y-%m-01),End=$(date +%Y-%m-01) \
  --granularity MONTHLY \
  --metrics BlendedCost

# セキュリティ設定確認
aws ec2 describe-security-groups --query 'SecurityGroups[?GroupName==`ProjectForestWebSG`].IpPermissions'

# パフォーマンス統計
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --start-time $(date -d '30 days ago' --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 86400 \
  --statistics Average,Maximum

echo "=== Monthly review completed ==="
```

## 緊急連絡先とエスカレーション

### 連絡先一覧

| 役割 | 担当者 | 連絡方法 | 対応時間 |
|------|--------|----------|----------|
| システム管理者 | [名前] | [電話/メール] | 24/7 |
| データベース管理者 | [名前] | [電話/メール] | 平日9-18時 |
| ネットワーク管理者 | [名前] | [電話/メール] | 24/7 |
| アプリケーション開発者 | [名前] | [電話/メール] | 平日9-20時 |

### エスカレーション基準

| レベル | 基準 | 対応者 | 対応時間 |
|--------|------|--------|----------|
| Level 1 | サービス完全停止 | システム管理者 | 即座 |
| Level 2 | パフォーマンス劣化 | 担当エンジニア | 1時間以内 |
| Level 3 | 機能の一部制限 | 開発チーム | 営業時間内 |

本トラブルシューティングガイドを参照することで、Project Forestの運用中に発生する様々な問題に迅速かつ適切に対応することができます。定期的にこのガイドを更新し、新しい問題や解決方法を追加していくことをお勧めします。