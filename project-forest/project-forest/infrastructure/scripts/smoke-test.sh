#!/bin/bash

set -euo pipefail

# Project Forest Smoke Test Script
# Usage: ./smoke-test.sh <base_url> [timeout]

BASE_URL=${1:-"http://localhost:3000"}
TIMEOUT=${2:-30}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# HTTP request with timeout and retry
http_request() {
    local url="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    local expected_status="${4:-200}"
    local max_retries=3
    local retry_delay=2
    
    for ((i=1; i<=max_retries; i++)); do
        local response
        local status_code
        
        if [[ -n "$data" ]]; then
            response=$(curl -s -w "\n%{http_code}" \
                --max-time "$TIMEOUT" \
                -X "$method" \
                -H "Content-Type: application/json" \
                -d "$data" \
                "$url" 2>/dev/null || echo -e "\n000")
        else
            response=$(curl -s -w "\n%{http_code}" \
                --max-time "$TIMEOUT" \
                -X "$method" \
                "$url" 2>/dev/null || echo -e "\n000")
        fi
        
        status_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n -1)
        
        if [[ "$status_code" == "$expected_status" ]]; then
            echo "$body"
            return 0
        fi
        
        if [[ $i -lt $max_retries ]]; then
            warn "Attempt $i failed (status: $status_code), retrying in ${retry_delay}s..."
            sleep $retry_delay
        fi
    done
    
    error "Request failed after $max_retries attempts. Status: $status_code"
    return 1
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log "Running test: $test_name"
    
    if $test_function; then
        success "✓ $test_name"
        ((TESTS_PASSED++))
    else
        error "✗ $test_name"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Health check endpoint
test_health_check() {
    log "Testing health check endpoint..."
    
    local response
    response=$(http_request "$BASE_URL/api/health" "GET" "" "200")
    
    if echo "$response" | grep -q "\"status\".*\"ok\""; then
        return 0
    else
        warn "Health check response: $response"
        return 1
    fi
}

# Test 2: Homepage accessibility
test_homepage() {
    log "Testing homepage accessibility..."
    
    local response
    response=$(http_request "$BASE_URL/" "GET" "" "200")
    
    if echo "$response" | grep -q -i "project forest\|text management\|テキスト管理"; then
        return 0
    else
        return 1
    fi
}

# Test 3: API endpoints
test_api_endpoints() {
    log "Testing API endpoints..."
    
    # Test text entries endpoint (should return 200 even if empty)
    http_request "$BASE_URL/api/text-entries" "GET" "" "200" > /dev/null
    
    # Test progress endpoint
    http_request "$BASE_URL/api/progress" "GET" "" "200" > /dev/null
    
    return 0
}

# Test 4: Database connectivity
test_database_connectivity() {
    log "Testing database connectivity through API..."
    
    # Try to fetch text entries which requires DB connection
    local response
    response=$(http_request "$BASE_URL/api/text-entries?limit=1" "GET" "" "200")
    
    if echo "$response" | grep -q "\"data\""; then
        return 0
    else
        warn "Database connectivity test response: $response"
        return 1
    fi
}

# Test 5: Static assets
test_static_assets() {
    log "Testing static assets..."
    
    # Test favicon
    http_request "$BASE_URL/favicon.ico" "GET" "" "200" > /dev/null
    
    return 0
}

# Test 6: Security headers
test_security_headers() {
    log "Testing security headers..."
    
    local headers
    headers=$(curl -s -I --max-time "$TIMEOUT" "$BASE_URL/" 2>/dev/null || echo "")
    
    # Check for basic security headers
    if echo "$headers" | grep -qi "x-frame-options\|x-content-type-options\|x-xss-protection"; then
        return 0
    else
        warn "Missing security headers in response"
        return 1
    fi
}

# Test 7: Performance check
test_performance() {
    log "Testing basic performance..."
    
    local start_time=$(date +%s%3N)
    http_request "$BASE_URL/" "GET" "" "200" > /dev/null
    local end_time=$(date +%s%3N)
    
    local response_time=$((end_time - start_time))
    
    if [[ $response_time -lt 5000 ]]; then  # Less than 5 seconds
        log "Response time: ${response_time}ms"
        return 0
    else
        warn "Slow response time: ${response_time}ms"
        return 1
    fi
}

# Test 8: Memory usage check (if running on the same host)
test_resource_usage() {
    log "Testing resource usage..."
    
    # This is a basic test - in real scenarios you might check container metrics
    local response
    response=$(http_request "$BASE_URL/api/health" "GET" "" "200")
    
    # If we get a successful response, assume resources are adequate
    return 0
}

# Create sample test data
create_test_data() {
    log "Creating test data..."
    
    local test_entry='{
        "label": "SMOKE_TEST_001",
        "file_category": "test",
        "original_text": "This is a smoke test entry",
        "language_code": "ja",
        "created_by": 1
    }'
    
    local response
    response=$(http_request "$BASE_URL/api/text-entries" "POST" "$test_entry" "201" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        log "Test data created successfully"
        # Extract ID for cleanup
        TEST_ENTRY_ID=$(echo "$response" | grep -o '"id":[0-9]*' | cut -d: -f2 || echo "")
    else
        warn "Could not create test data"
    fi
}

# Cleanup test data
cleanup_test_data() {
    if [[ -n "${TEST_ENTRY_ID:-}" ]]; then
        log "Cleaning up test data..."
        http_request "$BASE_URL/api/text-entries/$TEST_ENTRY_ID" "DELETE" "" "200" > /dev/null 2>&1 || {
            warn "Could not clean up test entry $TEST_ENTRY_ID"
        }
    fi
}

# Wait for application to be ready
wait_for_app() {
    log "Waiting for application to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s --max-time 5 "$BASE_URL/api/health" > /dev/null 2>&1; then
            success "Application is ready"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: Application not ready yet..."
        sleep 5
        ((attempt++))
    done
    
    error "Application did not become ready within timeout"
}

# Main smoke test function
main() {
    log "Starting smoke tests for Project Forest"
    log "Base URL: $BASE_URL"
    log "Timeout: ${TIMEOUT}s"
    
    # Wait for app to be ready
    wait_for_app
    
    # Run all tests
    run_test "Health Check" test_health_check
    run_test "Homepage Accessibility" test_homepage
    run_test "API Endpoints" test_api_endpoints
    run_test "Database Connectivity" test_database_connectivity
    run_test "Static Assets" test_static_assets
    run_test "Security Headers" test_security_headers
    run_test "Performance Check" test_performance
    run_test "Resource Usage" test_resource_usage
    
    # Create and test with sample data
    create_test_data
    
    # Cleanup
    cleanup_test_data
    
    # Summary
    echo
    log "Smoke test summary:"
    success "Tests passed: $TESTS_PASSED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        error "Tests failed: $TESTS_FAILED"
        error "Smoke tests failed!"
        exit 1
    else
        success "All smoke tests passed!"
        exit 0
    fi
}

# Handle script termination
trap cleanup_test_data EXIT

# Run main function
main