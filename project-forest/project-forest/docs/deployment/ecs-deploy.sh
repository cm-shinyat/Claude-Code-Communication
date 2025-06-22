#!/bin/bash
# ECS deployment script with aws-vault

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Variables
AWS_PROFILE=${AWS_PROFILE:-shinyat}
REGION=${AWS_REGION:-ap-northeast-1}
ENVIRONMENT=${1:-staging}
IMAGE_TAG=${2:-latest}

echo -e "${YELLOW}🚀 Starting ECS deployment for $ENVIRONMENT...${NC}"

# Get account ID
ACCOUNT_ID=$(aws-vault exec $AWS_PROFILE -- aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Create ECR repository if not exists
echo -e "${YELLOW}📦 Ensuring ECR repository exists...${NC}"
aws-vault exec $AWS_PROFILE -- aws ecr describe-repositories \
  --repository-names project-forest \
  --region $REGION 2>/dev/null || \
aws-vault exec $AWS_PROFILE -- aws ecr create-repository \
  --repository-name project-forest \
  --region $REGION

# Login to ECR
echo -e "${YELLOW}🔐 Logging in to ECR...${NC}"
aws-vault exec $AWS_PROFILE -- aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Build and push Docker image
echo -e "${YELLOW}🏗️  Building Docker image...${NC}"
# Use dev Dockerfile to avoid build errors
docker build -f infrastructure/docker/Dockerfile.dev -t project-forest:$IMAGE_TAG .

echo -e "${YELLOW}🏷️  Tagging image...${NC}"
docker tag project-forest:$IMAGE_TAG ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:$IMAGE_TAG

echo -e "${YELLOW}⬆️  Pushing to ECR...${NC}"
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/project-forest:$IMAGE_TAG

# Create log group if not exists
echo -e "${YELLOW}📝 Creating CloudWatch log group...${NC}"
aws-vault exec $AWS_PROFILE -- aws logs create-log-group \
  --log-group-name /ecs/project-forest-$ENVIRONMENT \
  --region $REGION 2>/dev/null || true

# Register task definition
echo -e "${YELLOW}📋 Registering task definition...${NC}"
# Update the image in task definition
sed "s/388450459156/${ACCOUNT_ID}/g" docs/deployment/task-definitions/${ENVIRONMENT}-simple.json > /tmp/task-def.json
aws-vault exec $AWS_PROFILE -- aws ecs register-task-definition \
  --cli-input-json file:///tmp/task-def.json \
  --region $REGION

# Check if cluster exists
echo -e "${YELLOW}🎯 Checking ECS cluster...${NC}"
if ! aws-vault exec $AWS_PROFILE -- aws ecs describe-clusters \
  --clusters project-forest-$ENVIRONMENT \
  --region $REGION | grep -q "ACTIVE"; then
  echo -e "${YELLOW}Creating ECS cluster...${NC}"
  aws-vault exec $AWS_PROFILE -- aws ecs create-cluster \
    --cluster-name project-forest-$ENVIRONMENT \
    --region $REGION
fi

echo -e "${GREEN}✅ Deployment preparation completed!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Create ECS service:"
echo "   aws-vault exec $AWS_PROFILE -- aws ecs create-service \\"
echo "     --cluster project-forest-$ENVIRONMENT \\"
echo "     --service-name project-forest-service \\"
echo "     --task-definition project-forest-$ENVIRONMENT \\"
echo "     --desired-count 1 \\"
echo "     --launch-type FARGATE \\"
echo "     --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}'"
echo ""
echo "2. Or update existing service:"
echo "   aws-vault exec $AWS_PROFILE -- aws ecs update-service \\"
echo "     --cluster project-forest-$ENVIRONMENT \\"
echo "     --service project-forest-service \\"
echo "     --task-definition project-forest-$ENVIRONMENT"