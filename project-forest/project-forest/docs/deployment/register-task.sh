#!/bin/bash
# Register ECS task definition

set -e

echo "📋 Registering ECS task definition..."

# Get account ID
ACCOUNT_ID=$(aws-vault exec shinyat -- aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Direct registration without file
aws-vault exec shinyat -- aws ecs register-task-definition \
  --family "project-forest-staging" \
  --network-mode "awsvpc" \
  --requires-compatibilities "FARGATE" \
  --cpu "256" \
  --memory "512" \
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
        {\"name\": \"NODE_ENV\", \"value\": \"production\"},
        {\"name\": \"PORT\", \"value\": \"3000\"},
        {\"name\": \"DB_HOST\", \"value\": \"localhost\"},
        {\"name\": \"DB_USER\", \"value\": \"root\"},
        {\"name\": \"DB_PASSWORD\", \"value\": \"password\"},
        {\"name\": \"DB_NAME\", \"value\": \"project_forest_staging\"}
      ],
      \"logConfiguration\": {
        \"logDriver\": \"awslogs\",
        \"options\": {
          \"awslogs-group\": \"/ecs/project-forest-staging\",
          \"awslogs-region\": \"ap-northeast-1\",
          \"awslogs-stream-prefix\": \"ecs\",
          \"awslogs-create-group\": \"true\"
        }
      }
    }
  ]" \
  --region ap-northeast-1

echo "✅ Task definition registered successfully!"