#!/bin/bash

# ローカル本番環境テストスクリプト
set -e

echo "🏭 ローカル本番環境テスト開始"

# 1. 既存コンテナ停止・削除
echo "🧹 既存コンテナクリーンアップ..."
docker-compose -f docker-compose.prod.yml down -v 2>/dev/null || true

# 2. 本番用イメージビルド
echo "🔨 本番用イメージビルド..."
docker-compose -f docker-compose.prod.yml build --no-cache

# 3. 本番環境起動
echo "🚀 本番環境起動..."
docker-compose -f docker-compose.prod.yml up -d

# 4. ヘルスチェック待機
echo "⏳ アプリケーション起動待機..."
timeout=120
count=0

while [ $count -lt $timeout ]; do
  if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
    echo "✅ アプリケーション起動完了！"
    break
  fi
  
  echo "⏳ 起動待機中... ($count/$timeout)"
  sleep 2
  count=$((count + 2))
done

if [ $count -ge $timeout ]; then
  echo "❌ アプリケーション起動タイムアウト"
  echo "📝 ログ確認:"
  docker-compose -f docker-compose.prod.yml logs app
  exit 1
fi

# 5. 基本動作テスト
echo "🧪 基本動作テスト実行..."

# ヘルスチェック
echo "- ヘルスチェック"
curl -s http://localhost:3000/api/health | jq .

# API動作確認
echo "- API動作確認"
echo "  - Characters API"
curl -s http://localhost:3000/api/characters | jq '. | length'

echo "  - Tags API"
curl -s http://localhost:3000/api/tags | jq '. | length'

echo "  - Proper Nouns API"
curl -s http://localhost:3000/api/proper-nouns | jq '. | length'

echo "  - Forbidden Words API"
curl -s http://localhost:3000/api/forbidden-words | jq '. | length'

echo "  - Styles API"
curl -s http://localhost:3000/api/styles | jq '. | length'

# 管理画面アクセステスト
echo "- 管理画面アクセステスト"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/admin)
if [ "$STATUS" -eq 200 ]; then
  echo "  ✅ 管理画面正常"
else
  echo "  ❌ 管理画面エラー (HTTP $STATUS)"
fi

echo ""
echo "🎉 ローカル本番環境テスト完了！"
echo "🌐 アプリケーション: http://localhost:3000"
echo "⚙️  管理画面: http://localhost:3000/admin"
echo ""
echo "📝 ログ確認: docker-compose -f docker-compose.prod.yml logs -f"
echo "🛑 停止: docker-compose -f docker-compose.prod.yml down"