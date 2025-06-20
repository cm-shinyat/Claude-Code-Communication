#!/bin/bash

set -euo pipefail

# Project Forest Deployment Script
# Usage: ./deploy.sh <environment> <image_tag>

ENVIRONMENT=${1:-staging}
IMAGE_TAG=${2:-latest}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        staging|production)
            log "Deploying to $ENVIRONMENT environment"
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT. Must be 'staging' or 'production'"
            ;;
    esac
}

# Check required tools
check_requirements() {
    log "Checking deployment requirements..."
    
    local required_tools=("kubectl" "docker" "envsubst")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
    
    # Check kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi
    
    success "All requirements satisfied"
}

# Load environment variables
load_env_vars() {
    local env_file="${SCRIPT_DIR}/../configs/${ENVIRONMENT}.env"
    
    if [[ -f "$env_file" ]]; then
        log "Loading environment variables from $env_file"
        set -a
        source "$env_file"
        set +a
    else
        warn "Environment file $env_file not found, using defaults"
    fi
    
    # Set default values
    export NAMESPACE=${NAMESPACE:-"project-forest-${ENVIRONMENT}"}
    export REPLICA_COUNT=${REPLICA_COUNT:-3}
    export DB_HOST=${DB_HOST:-"mysql-service"}
    export DB_PORT=${DB_PORT:-3306}
    export APP_PORT=${APP_PORT:-3000}
    export REGISTRY=${REGISTRY:-"ghcr.io"}
    export IMAGE_REPOSITORY=${IMAGE_REPOSITORY:-"project-forest/project-forest"}
}

# Create namespace if it doesn't exist
ensure_namespace() {
    log "Ensuring namespace $NAMESPACE exists..."
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl create namespace "$NAMESPACE"
        success "Created namespace $NAMESPACE"
    else
        log "Namespace $NAMESPACE already exists"
    fi
}

# Deploy secrets
deploy_secrets() {
    log "Deploying secrets..."
    
    # Create database secret
    kubectl create secret generic db-secret \
        --namespace="$NAMESPACE" \
        --from-literal=host="$DB_HOST" \
        --from-literal=port="$DB_PORT" \
        --from-literal=username="$DB_USER" \
        --from-literal=password="$DB_PASSWORD" \
        --from-literal=database="$DB_NAME" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create app secrets (JWT, API keys, etc.)
    kubectl create secret generic app-secret \
        --namespace="$NAMESPACE" \
        --from-literal=jwt-secret="${JWT_SECRET:-$(openssl rand -base64 32)}" \
        --from-literal=api-key="${API_KEY:-$(openssl rand -hex 16)}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    success "Secrets deployed"
}

# Deploy configmap
deploy_configmap() {
    log "Deploying configmap..."
    
    local configmap_file="${SCRIPT_DIR}/../configs/configmap.yml"
    envsubst < "$configmap_file" | kubectl apply -f -
    
    success "Configmap deployed"
}

# Deploy application
deploy_application() {
    log "Deploying application with image: $IMAGE_TAG"
    
    local deployment_file="${SCRIPT_DIR}/../configs/deployment.yml"
    local service_file="${SCRIPT_DIR}/../configs/service.yml"
    local ingress_file="${SCRIPT_DIR}/../configs/ingress.yml"
    
    # Set image tag
    export IMAGE_TAG
    
    # Deploy application
    envsubst < "$deployment_file" | kubectl apply -f -
    envsubst < "$service_file" | kubectl apply -f -
    envsubst < "$ingress_file" | kubectl apply -f -
    
    success "Application deployed"
}

# Wait for deployment to be ready
wait_for_deployment() {
    log "Waiting for deployment to be ready..."
    
    if kubectl rollout status deployment/project-forest-app -n "$NAMESPACE" --timeout=600s; then
        success "Deployment is ready"
    else
        error "Deployment failed to become ready"
    fi
}

# Run post-deployment tasks
post_deployment() {
    log "Running post-deployment tasks..."
    
    # Scale deployment based on environment
    if [[ "$ENVIRONMENT" == "production" ]]; then
        kubectl scale deployment project-forest-app --replicas="$REPLICA_COUNT" -n "$NAMESPACE"
    fi
    
    # Update deployment annotation
    kubectl annotate deployment project-forest-app -n "$NAMESPACE" \
        deployment.kubernetes.io/revision- \
        deployment.kubernetes.io/deployed-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        deployment.kubernetes.io/deployed-by="${USER:-cicd}" \
        deployment.kubernetes.io/image-tag="$IMAGE_TAG"
    
    success "Post-deployment tasks completed"
}

# Get deployment status
get_status() {
    log "Deployment status:"
    echo
    kubectl get pods -n "$NAMESPACE" -l app=project-forest
    echo
    kubectl get services -n "$NAMESPACE"
    echo
    kubectl get ingress -n "$NAMESPACE"
    echo
    
    # Get application URL
    local app_url
    if [[ "$ENVIRONMENT" == "production" ]]; then
        app_url="https://project-forest.example.com"
    else
        app_url="https://staging.project-forest.example.com"
    fi
    
    success "Application deployed successfully!"
    success "URL: $app_url"
}

# Rollback deployment
rollback() {
    warn "Rolling back deployment..."
    kubectl rollout undo deployment/project-forest-app -n "$NAMESPACE"
    kubectl rollout status deployment/project-forest-app -n "$NAMESPACE" --timeout=300s
    success "Rollback completed"
}

# Cleanup old replicasets
cleanup() {
    log "Cleaning up old replicasets..."
    kubectl delete replicaset -n "$NAMESPACE" \
        --selector=app=project-forest \
        --field-selector=status.replicas=0 \
        --ignore-not-found=true
    success "Cleanup completed"
}

# Main deployment function
main() {
    log "Starting deployment of Project Forest to $ENVIRONMENT"
    log "Image tag: $IMAGE_TAG"
    
    validate_environment
    check_requirements
    load_env_vars
    ensure_namespace
    deploy_secrets
    deploy_configmap
    deploy_application
    wait_for_deployment
    post_deployment
    get_status
    cleanup
    
    success "Deployment completed successfully!"
}

# Handle script arguments
case "${1:-deploy}" in
    rollback)
        rollback
        ;;
    status)
        get_status
        ;;
    cleanup)
        cleanup
        ;;
    *)
        main
        ;;
esac