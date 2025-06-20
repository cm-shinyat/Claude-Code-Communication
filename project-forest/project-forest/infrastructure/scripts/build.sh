#!/bin/bash

set -euo pipefail

# Project Forest Build Script
# Usage: ./build.sh [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values
BUILD_ENV=${BUILD_ENV:-production}
DOCKER_BUILD=${DOCKER_BUILD:-false}
PUSH_IMAGE=${PUSH_IMAGE:-false}
IMAGE_TAG=${IMAGE_TAG:-latest}
REGISTRY=${REGISTRY:-ghcr.io}
IMAGE_REPOSITORY=${IMAGE_REPOSITORY:-project-forest/project-forest}

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

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Project Forest Build Script

OPTIONS:
    -e, --env ENV           Build environment (development|staging|production) [default: production]
    -d, --docker            Build Docker image
    -p, --push              Push Docker image to registry (requires --docker)
    -t, --tag TAG           Docker image tag [default: latest]
    -r, --registry URL      Container registry URL [default: ghcr.io]
    --repo REPO             Image repository name [default: project-forest/project-forest]
    --no-cache              Build without cache
    --skip-tests            Skip running tests
    --skip-lint             Skip linting
    -h, --help              Show this help message

EXAMPLES:
    $0                                  # Basic build
    $0 -e staging                       # Build for staging
    $0 -d -t v1.2.3                     # Build Docker image with tag
    $0 -d -p -t latest                  # Build and push Docker image
    $0 --no-cache --skip-tests          # Build without cache, skip tests

EOF
}

# Parse command line arguments
parse_args() {
    local no_cache=false
    local skip_tests=false
    local skip_lint=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--env)
                BUILD_ENV="$2"
                shift 2
                ;;
            -d|--docker)
                DOCKER_BUILD=true
                shift
                ;;
            -p|--push)
                PUSH_IMAGE=true
                shift
                ;;
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            --repo)
                IMAGE_REPOSITORY="$2"
                shift 2
                ;;
            --no-cache)
                no_cache=true
                shift
                ;;
            --skip-tests)
                skip_tests=true
                shift
                ;;
            --skip-lint)
                skip_lint=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Export variables for use in other functions
    export NO_CACHE=$no_cache
    export SKIP_TESTS=$skip_tests
    export SKIP_LINT=$skip_lint
}

# Validate build environment
validate_environment() {
    case $BUILD_ENV in
        development|staging|production)
            log "Building for $BUILD_ENV environment"
            ;;
        *)
            error "Invalid build environment: $BUILD_ENV. Must be 'development', 'staging', or 'production'"
            ;;
    esac
}

# Check required tools
check_requirements() {
    log "Checking build requirements..."
    
    local required_tools=("node" "npm")
    if [[ "$DOCKER_BUILD" == "true" ]]; then
        required_tools+=("docker")
    fi
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
    
    # Check Node.js version
    local node_version
    node_version=$(node --version | cut -d'v' -f2)
    local major_version
    major_version=$(echo "$node_version" | cut -d'.' -f1)
    
    if [[ $major_version -lt 18 ]]; then
        error "Node.js 18 or higher is required (current: $node_version)"
    fi
    
    success "All requirements satisfied"
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."
    
    cd "$PROJECT_ROOT"
    
    if [[ "$BUILD_ENV" == "production" ]]; then
        npm ci --only=production --ignore-scripts
    else
        npm ci
    fi
    
    success "Dependencies installed"
}

# Run linting
run_lint() {
    if [[ "$SKIP_LINT" == "true" ]]; then
        warn "Skipping linting"
        return 0
    fi
    
    log "Running linting checks..."
    
    cd "$PROJECT_ROOT"
    
    # Run ESLint
    if npm run lint; then
        success "Linting passed"
    else
        error "Linting failed"
    fi
    
    # Run TypeScript type checking
    if npx tsc --noEmit; then
        success "Type checking passed"
    else
        error "Type checking failed"
    fi
}

# Run tests
run_tests() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        warn "Skipping tests"
        return 0
    fi
    
    log "Running tests..."
    
    cd "$PROJECT_ROOT"
    
    # Set test environment
    export NODE_ENV=test
    
    if npm test; then
        success "Tests passed"
    else
        error "Tests failed"
    fi
}

# Build application
build_app() {
    log "Building application for $BUILD_ENV..."
    
    cd "$PROJECT_ROOT"
    
    # Set build environment
    export NODE_ENV=$BUILD_ENV
    export NEXT_TELEMETRY_DISABLED=1
    
    # Run build
    if [[ "$NO_CACHE" == "true" ]]; then
        rm -rf .next
        log "Removed build cache"
    fi
    
    if npm run build; then
        success "Application build completed"
    else
        error "Application build failed"
    fi
    
    # Generate build info
    generate_build_info
}

# Generate build information
generate_build_info() {
    log "Generating build information..."
    
    local build_info_file="$PROJECT_ROOT/.next/build-info.json"
    local git_commit
    local git_branch
    local build_time
    
    git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    build_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$build_info_file" << EOF
{
  "version": "${IMAGE_TAG}",
  "environment": "${BUILD_ENV}",
  "gitCommit": "${git_commit}",
  "gitBranch": "${git_branch}",
  "buildTime": "${build_time}",
  "nodeVersion": "$(node --version)",
  "npmVersion": "$(npm --version)"
}
EOF
    
    success "Build information generated"
}

# Build Docker image
build_docker_image() {
    if [[ "$DOCKER_BUILD" != "true" ]]; then
        return 0
    fi
    
    log "Building Docker image..."
    
    cd "$PROJECT_ROOT"
    
    local image_name="${REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    local build_args=(
        --file infrastructure/docker/Dockerfile
        --tag "$image_name"
        --label "build.environment=$BUILD_ENV"
        --label "build.version=$IMAGE_TAG"
        --label "build.timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        --label "vcs.ref=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
        --label "vcs.url=$(git config --get remote.origin.url 2>/dev/null || echo unknown)"
    )
    
    if [[ "$NO_CACHE" == "true" ]]; then
        build_args+=(--no-cache)
    fi
    
    if docker build "${build_args[@]}" .; then
        success "Docker image built: $image_name"
    else
        error "Docker image build failed"
    fi
    
    # Show image size
    local image_size
    image_size=$(docker images "$image_name" --format "table {{.Size}}" | tail -n +2)
    log "Image size: $image_size"
}

# Push Docker image
push_docker_image() {
    if [[ "$PUSH_IMAGE" != "true" || "$DOCKER_BUILD" != "true" ]]; then
        return 0
    fi
    
    log "Pushing Docker image..."
    
    local image_name="${REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    
    if docker push "$image_name"; then
        success "Docker image pushed: $image_name"
    else
        error "Docker image push failed"
    fi
}

# Security scan
security_scan() {
    if [[ "$DOCKER_BUILD" != "true" ]]; then
        return 0
    fi
    
    log "Running security scan..."
    
    local image_name="${REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    
    # Check if Trivy is available
    if command -v trivy &> /dev/null; then
        if trivy image --exit-code 1 --severity HIGH,CRITICAL "$image_name"; then
            success "Security scan passed"
        else
            warn "Security vulnerabilities found"
        fi
    else
        warn "Trivy not found, skipping security scan"
    fi
}

# Cleanup build artifacts
cleanup() {
    log "Cleaning up build artifacts..."
    
    cd "$PROJECT_ROOT"
    
    # Remove node_modules if we're in CI
    if [[ "${CI:-false}" == "true" ]]; then
        rm -rf node_modules
        log "Removed node_modules"
    fi
    
    # Clean Docker build cache (if requested)
    if [[ "$DOCKER_BUILD" == "true" && "$NO_CACHE" == "true" ]]; then
        docker builder prune -f
        log "Cleaned Docker build cache"
    fi
    
    success "Cleanup completed"
}

# Generate build report
generate_report() {
    log "Generating build report..."
    
    local report_file="$PROJECT_ROOT/build-report.json"
    local end_time
    local duration
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    cat > "$report_file" << EOF
{
  "status": "success",
  "environment": "${BUILD_ENV}",
  "duration": ${duration},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "imageTag": "${IMAGE_TAG}",
  "dockerBuild": ${DOCKER_BUILD},
  "pushed": ${PUSH_IMAGE},
  "skipTests": ${SKIP_TESTS},
  "skipLint": ${SKIP_LINT}
}
EOF
    
    success "Build report generated: $report_file"
}

# Main build function
main() {
    local start_time
    start_time=$(date +%s)
    
    log "Starting Project Forest build"
    log "Environment: $BUILD_ENV"
    log "Docker build: $DOCKER_BUILD"
    log "Push image: $PUSH_IMAGE"
    log "Image tag: $IMAGE_TAG"
    
    validate_environment
    check_requirements
    install_dependencies
    run_lint
    run_tests
    build_app
    build_docker_image
    security_scan
    push_docker_image
    cleanup
    generate_report
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    success "Build completed successfully in ${duration}s!"
}

# Handle script termination
trap 'error "Build interrupted"' INT TERM

# Parse arguments and run main function
parse_args "$@"
main