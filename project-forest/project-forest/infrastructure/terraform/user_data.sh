# ECS/Fargate Migration Notice
# This file is no longer used in the ECS/Fargate configuration
# ECS tasks are managed through task definitions and do not use user data scripts

# Historical EC2 user data script (for reference only)
# This script was used for EC2-based deployments
# ECS/Fargate deployments use container images instead

echo "This user_data.sh file is no longer used in ECS/Fargate deployments"
echo "Container initialization is handled through:"
echo "1. Docker images (see Dockerfile in project root)"
echo "2. ECS task definitions (see main.tf)"
echo "3. Environment variables in task definition"
echo ""
echo "For ECS deployment, ensure your Docker image includes:"
echo "- Application code"
echo "- Runtime dependencies (Node.js, npm packages)"
echo "- Startup scripts"
echo ""
echo "Configuration is passed through environment variables:"
echo "- DB_HOST, DB_NAME, DB_USER, DB_PASSWORD"
echo "- JWT_SECRET"
echo "- NODE_ENV, PORT"