#!/bin/bash

# Project Forest ビルドとデプロイスクリプト
set -e

# 設定
export AWS_REGION=ap-northeast-1
export PROJECT_NAME=project-forest
export ECR_REPOSITORY_NAME=${PROJECT_NAME}

echo "🏗️  Project Forest デプロイ開始"

# 1. ECR URI取得
echo "📦 ECR URI取得中..."
export ECR_URI=$(aws-vault exec shinyat -- aws ecr describe-repositories \
  --repository-names ${ECR_REPOSITORY_NAME} \
  --region ${AWS_REGION} \
  --query 'repositories[0].repositoryUri' \
  --output text)

if [ -z "$ECR_URI" ]; then
  echo "❌ ECRリポジトリが見つかりません。先にECRリポジトリを作成してください。"
  exit 1
fi

echo "✅ ECR URI: ${ECR_URI}"

# 2. ECRログイン
echo "🔐 ECRにログイン中..."
aws-vault exec shinyat -- aws ecr get-login-password \
  --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URI}

# 3. バージョンタグ生成
VERSION_TAG=$(date +"%Y%m%d-%H%M%S")
echo "🏷️  バージョンタグ: ${VERSION_TAG}"

# 4. Dockerビルド
echo "🔨 Dockerイメージビルド中..."
docker build --platform linux/amd64 -t ${ECR_REPOSITORY_NAME}:${VERSION_TAG} -f Dockerfile.prod .

# 5. タグ付け
echo "🏷️  イメージタグ付け中..."
docker tag ${ECR_REPOSITORY_NAME}:${VERSION_TAG} ${ECR_URI}:${VERSION_TAG}
docker tag ${ECR_REPOSITORY_NAME}:${VERSION_TAG} ${ECR_URI}:latest

# 6. プッシュ
echo "⬆️  イメージプッシュ中..."
docker push ${ECR_URI}:${VERSION_TAG}
docker push ${ECR_URI}:latest

# 7. ECSサービス更新
echo "🚀 ECSサービス更新中..."
export CLUSTER_NAME=${PROJECT_NAME}-cluster
export SERVICE_NAME=${PROJECT_NAME}-service

# サービス強制更新（新しいイメージを取得）
aws-vault exec shinyat -- aws ecs update-service \
  --cluster ${CLUSTER_NAME} \
  --service ${SERVICE_NAME} \
  --force-new-deployment

echo "✅ デプロイ完了！"
echo "📊 デプロイ状況確認: aws-vault exec shinyat -- aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME}"
echo "📝 ログ確認: aws-vault exec shinyat -- aws logs tail /ecs/${PROJECT_NAME} --follow"