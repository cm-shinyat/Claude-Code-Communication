#!/bin/bash
# Simple ECS deployment that works

set -e

echo "🚀 Simple ECS deployment starting..."

# Get account ID
ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws-vault exec shinyat -- aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com

# Build with dev Dockerfile (no build errors)
echo "🏗️  Building with dev Dockerfile..."
docker build -f infrastructure/docker/Dockerfile.dev -t project-forest:latest .

# Tag and push
docker tag project-forest:latest ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest
docker push ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/project-forest:latest

# Create log group
aws-vault exec shinyat -- aws logs create-log-group \
  --log-group-name /ecs/project-forest-staging \
  --region ap-northeast-1 2>/dev/null || true

# Register task definition
# First update the JSON file with correct account ID
sed "s/388450459156/${ACCOUNT_ID}/g" docs/deployment/task-definitions/staging-simple.json > /tmp/task-definition.json

# Then register it
aws-vault exec shinyat -- aws ecs register-task-definition \
  --cli-input-json file:///tmp/task-definition.json \
  --region ap-northeast-1

echo "✅ Deployment completed!"
echo ""
echo "If you need to create a service:"
echo "aws-vault exec shinyat -- aws ecs create-service \\"
echo "  --cluster default \\"
echo "  --service-name project-forest \\"
echo "  --task-definition project-forest-staging \\"
echo "  --desired-count 1 \\"
echo "  --launch-type FARGATE \\"
echo "  --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}'"