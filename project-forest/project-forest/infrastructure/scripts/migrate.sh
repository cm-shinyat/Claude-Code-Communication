#!/bin/bash

set -euo pipefail

# Project Forest Database Migration Script
# Usage: ./migrate.sh <environment> [migration_file]

ENVIRONMENT=${1:-staging}
MIGRATION_FILE=${2:-""}
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

# Load environment configuration
load_config() {
    local env_file="${SCRIPT_DIR}/../configs/${ENVIRONMENT}.env"
    
    if [[ -f "$env_file" ]]; then
        log "Loading database configuration for $ENVIRONMENT"
        set -a
        source "$env_file"
        set +a
    else
        error "Environment configuration file not found: $env_file"
    fi
    
    # Validate required variables
    for var in DB_HOST DB_USER DB_PASSWORD DB_NAME; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable $var is not set"
        fi
    done
}

# Check database connection
check_connection() {
    log "Testing database connection..."
    
    if mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" &> /dev/null; then
        success "Database connection successful"
    else
        error "Cannot connect to database"
    fi
}

# Create migrations table if it doesn't exist
ensure_migrations_table() {
    log "Ensuring migrations table exists..."
    
    mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" <<EOF
CREATE TABLE IF NOT EXISTS schema_migrations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    version VARCHAR(255) NOT NULL UNIQUE,
    filename VARCHAR(255) NOT NULL,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    checksum VARCHAR(255) NOT NULL,
    execution_time_ms INT,
    INDEX idx_version (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF
    
    success "Migrations table ready"
}

# Calculate file checksum
calculate_checksum() {
    local file="$1"
    sha256sum "$file" | cut -d' ' -f1
}

# Check if migration was already applied
is_migration_applied() {
    local version="$1"
    local checksum="$2"
    
    local count
    count=$(mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" -N -s "$DB_NAME" \
        -e "SELECT COUNT(*) FROM schema_migrations WHERE version = '$version' AND checksum = '$checksum';")
    
    [[ "$count" -gt 0 ]]
}

# Record migration execution
record_migration() {
    local version="$1"
    local filename="$2"
    local checksum="$3"
    local execution_time="$4"
    
    mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
        -e "INSERT INTO schema_migrations (version, filename, checksum, execution_time_ms) 
            VALUES ('$version', '$filename', '$checksum', $execution_time)
            ON DUPLICATE KEY UPDATE 
                executed_at = CURRENT_TIMESTAMP,
                checksum = '$checksum',
                execution_time_ms = $execution_time;"
}

# Execute single migration file
execute_migration() {
    local migration_file="$1"
    local filename=$(basename "$migration_file")
    local version="${filename%.*}"  # Remove extension
    local checksum=$(calculate_checksum "$migration_file")
    
    if is_migration_applied "$version" "$checksum"; then
        log "Migration $filename already applied with same checksum, skipping"
        return 0
    fi
    
    log "Executing migration: $filename"
    
    # Backup database before migration (production only)
    if [[ "$ENVIRONMENT" == "production" ]]; then
        backup_database "$version"
    fi
    
    # Execute migration with timing
    local start_time=$(date +%s%3N)
    
    if mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$migration_file"; then
        local end_time=$(date +%s%3N)
        local execution_time=$((end_time - start_time))
        
        record_migration "$version" "$filename" "$checksum" "$execution_time"
        success "Migration $filename completed in ${execution_time}ms"
    else
        error "Migration $filename failed"
    fi
}

# Backup database (production only)
backup_database() {
    local version="$1"
    local backup_dir="${PROJECT_ROOT}/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/backup_${ENVIRONMENT}_${timestamp}_pre_${version}.sql"
    
    mkdir -p "$backup_dir"
    
    log "Creating database backup: $backup_file"
    
    mysqldump -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" \
        --single-transaction --routines --triggers "$DB_NAME" > "$backup_file"
    
    # Compress backup
    gzip "$backup_file"
    
    success "Database backup created: ${backup_file}.gz"
}

# Run all pending migrations
run_migrations() {
    local migrations_dir="${PROJECT_ROOT}/database/migrations"
    
    if [[ ! -d "$migrations_dir" ]]; then
        log "No migrations directory found, running base schema"
        execute_migration "${PROJECT_ROOT}/database/schema.sql"
        return 0
    fi
    
    log "Looking for migration files in $migrations_dir"
    
    # Find all .sql files and sort them
    local migration_files=($(find "$migrations_dir" -name "*.sql" | sort))
    
    if [[ ${#migration_files[@]} -eq 0 ]]; then
        warn "No migration files found"
        return 0
    fi
    
    log "Found ${#migration_files[@]} migration files"
    
    for migration_file in "${migration_files[@]}"; do
        execute_migration "$migration_file"
    done
}

# Run specific migration file
run_specific_migration() {
    local migration_file="$1"
    
    if [[ ! -f "$migration_file" ]]; then
        error "Migration file not found: $migration_file"
    fi
    
    log "Running specific migration: $migration_file"
    execute_migration "$migration_file"
}

# Show migration status
show_status() {
    log "Migration status for $ENVIRONMENT:"
    echo
    
    mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
        -e "SELECT version, filename, executed_at, execution_time_ms 
            FROM schema_migrations 
            ORDER BY executed_at DESC 
            LIMIT 20;" 2>/dev/null || {
        warn "Migrations table not found or empty"
    }
}

# Rollback last migration (use with extreme caution)
rollback_migration() {
    if [[ "$ENVIRONMENT" != "staging" ]]; then
        error "Migration rollback is only allowed in staging environment"
    fi
    
    warn "Rolling back last migration..."
    warn "This operation should only be used in development/staging!"
    
    read -p "Are you sure you want to rollback? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log "Rollback cancelled"
        return 0
    fi
    
    # Get last migration
    local last_version
    last_version=$(mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" -N -s "$DB_NAME" \
        -e "SELECT version FROM schema_migrations ORDER BY executed_at DESC LIMIT 1;" 2>/dev/null || echo "")
    
    if [[ -z "$last_version" ]]; then
        warn "No migrations to rollback"
        return 0
    fi
    
    # Look for rollback file
    local rollback_file="${PROJECT_ROOT}/database/rollbacks/${last_version}_rollback.sql"
    
    if [[ -f "$rollback_file" ]]; then
        log "Executing rollback for version: $last_version"
        mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$rollback_file"
        
        # Remove migration record
        mysql -h"$DB_HOST" -P"${DB_PORT:-3306}" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
            -e "DELETE FROM schema_migrations WHERE version = '$last_version';"
        
        success "Rollback completed for version: $last_version"
    else
        error "Rollback file not found: $rollback_file"
    fi
}

# Main function
main() {
    log "Starting database migration for $ENVIRONMENT"
    
    load_config
    check_connection
    ensure_migrations_table
    
    if [[ -n "$MIGRATION_FILE" ]]; then
        run_specific_migration "$MIGRATION_FILE"
    else
        run_migrations
    fi
    
    show_status
    success "Migration process completed"
}

# Handle command line arguments
case "${2:-migrate}" in
    status)
        load_config
        check_connection
        show_status
        ;;
    rollback)
        load_config
        check_connection
        ensure_migrations_table
        rollback_migration
        ;;
    *)
        main
        ;;
esac