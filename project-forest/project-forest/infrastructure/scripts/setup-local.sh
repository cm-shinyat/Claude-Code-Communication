#!/bin/bash

set -euo pipefail

# Project Forest Local Development Setup Script
# Usage: ./setup-local.sh [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values
RESET_DB=${RESET_DB:-false}
INSTALL_DEPS=${INSTALL_DEPS:-true}
START_SERVICES=${START_SERVICES:-true}
SKIP_DB_SETUP=${SKIP_DB_SETUP:-false}

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

Project Forest Local Development Setup Script

OPTIONS:
    --reset-db              Reset database (drop and recreate)
    --skip-deps             Skip dependency installation
    --skip-services         Skip starting services
    --skip-db               Skip database setup
    -h, --help              Show this help message

EXAMPLES:
    $0                      # Full setup
    $0 --reset-db           # Reset database and setup
    $0 --skip-deps          # Setup without installing dependencies

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reset-db)
                RESET_DB=true
                shift
                ;;
            --skip-deps)
                INSTALL_DEPS=false
                shift
                ;;
            --skip-services)
                START_SERVICES=false
                shift
                ;;
            --skip-db)
                SKIP_DB_SETUP=true
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
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    local required_tools=("node" "npm" "mysql" "git")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Check Node.js version
    local node_version
    node_version=$(node --version | cut -d'v' -f2)
    local major_version
    major_version=$(echo "$node_version" | cut -d'.' -f1)
    
    if [[ $major_version -lt 18 ]]; then
        error "Node.js 18 or higher is required (current: $node_version)"
    fi
    
    success "System requirements satisfied"
}

# Install dependencies
install_dependencies() {
    if [[ "$INSTALL_DEPS" != "true" ]]; then
        warn "Skipping dependency installation"
        return 0
    fi
    
    log "Installing dependencies..."
    
    cd "$PROJECT_ROOT"
    
    if npm ci; then
        success "Dependencies installed"
    else
        error "Failed to install dependencies"
    fi
}

# Setup environment files
setup_environment() {
    log "Setting up environment files..."
    
    cd "$PROJECT_ROOT"
    
    # Create .env.local if it doesn't exist
    if [[ ! -f ".env.local" ]]; then
        cat > .env.local << EOF
# Project Forest - Local Development Environment

# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=password
DB_NAME=project_forest_dev

# Application Settings
NODE_ENV=development
APP_PORT=3000
APP_HOST=localhost

# Authentication
JWT_SECRET=your-dev-jwt-secret-key-change-in-production
SESSION_SECRET=your-dev-session-secret-change-in-production

# API Keys (optional for local development)
DEEPL_API_KEY=your-deepl-api-key
GOOGLE_TRANSLATE_API_KEY=your-google-translate-api-key

# Feature Flags
ENABLE_TRANSLATION_API=false
ENABLE_CSV_IMPORT=true
ENABLE_WEBSOCKETS=true
ENABLE_AUDIT_LOG=true

# Logging
LOG_LEVEL=debug
LOG_FORMAT=pretty

# File Upload
MAX_FILE_SIZE=10485760
UPLOAD_DIR=./uploads

EOF
        success "Created .env.local file"
    else
        log ".env.local already exists"
    fi
    
    # Create uploads directory
    mkdir -p uploads logs tmp
    success "Created necessary directories"
}

# Setup database
setup_database() {
    if [[ "$SKIP_DB_SETUP" == "true" ]]; then
        warn "Skipping database setup"
        return 0
    fi
    
    log "Setting up database..."
    
    # Source environment variables
    if [[ -f "$PROJECT_ROOT/.env.local" ]]; then
        set -a
        source "$PROJECT_ROOT/.env.local"
        set +a
    fi
    
    # Default database settings
    DB_HOST=${DB_HOST:-localhost}
    DB_PORT=${DB_PORT:-3306}
    DB_USER=${DB_USER:-root}
    DB_PASSWORD=${DB_PASSWORD:-password}
    DB_NAME=${DB_NAME:-project_forest_dev}
    
    # Test database connection
    if ! mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" &> /dev/null; then
        error "Cannot connect to MySQL. Please ensure MySQL is running and credentials are correct."
    fi
    
    # Reset database if requested
    if [[ "$RESET_DB" == "true" ]]; then
        log "Resetting database..."
        mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -e "DROP DATABASE IF EXISTS $DB_NAME;"
    fi
    
    # Create database
    log "Creating database if not exists..."
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    # Run schema
    log "Setting up database schema..."
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$PROJECT_ROOT/database/schema.sql"
    
    # Create sample data
    create_sample_data
    
    success "Database setup completed"
}

# Create sample data for development
create_sample_data() {
    log "Creating sample data..."
    
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << EOF
-- Insert sample users
INSERT INTO users (username, email, password_hash, role) VALUES
('admin', 'admin@example.com', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LenevEyLRKS.CqoEq', 'admin'),
('writer', 'writer@example.com', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LenevEyLRKS.CqoEq', 'scenario_writer'),
('translator', 'translator@example.com', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LenevEyLRKS.CqoEq', 'translator'),
('reviewer', 'reviewer@example.com', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LenevEyLRKS.CqoEq', 'reviewer')
ON DUPLICATE KEY UPDATE username=VALUES(username);

-- Insert sample text entries
INSERT INTO text_entries (label, file_category, original_text, language_code, status, max_chars, max_lines, created_by, updated_by) VALUES
('MENU_001', 'メニュー', 'ゲームを開始する', 'ja', '未処理', 20, 1, 1, 1),
('MENU_002', 'メニュー', '設定', 'ja', '完了', 10, 1, 1, 1),
('MENU_003', 'メニュー', '終了', 'ja', '完了', 10, 1, 1, 1),
('DIALOG_001', 'ダイアログ', 'こんにちは！元気ですか？', 'ja', '確認依頼', 50, 2, 2, 2),
('DIALOG_002', 'ダイアログ', 'ありがとうございます。', 'ja', '完了', 30, 1, 2, 2),
('ERROR_001', 'エラー', 'ファイルが見つかりません', 'ja', '未処理', 40, 1, 1, 1)
ON DUPLICATE KEY UPDATE label=VALUES(label);

-- Insert sample translations
INSERT INTO translations (text_entry_id, language_code, translated_text, status, translator_id) VALUES
(2, 'en', 'Settings', '完了', 3),
(3, 'en', 'Exit', '完了', 3),
(5, 'en', 'Thank you.', '完了', 3)
ON DUPLICATE KEY UPDATE translated_text=VALUES(translated_text);

-- Insert sample characters
INSERT INTO characters (name, pronoun_first, pronoun_second, description, traits, created_by) VALUES
('主人公', '俺', '俺', '物語の主人公。勇敢で正義感が強い。', '勇敢、正義感、リーダーシップ', 2),
('ヒロイン', '私', '私', '物語のヒロイン。賢くて優しい。', '賢明、優しさ、癒し', 2),
('悪役', '我', '我輩', '物語の悪役。狡猾で野心的。', '狡猾、野心、カリスマ', 2)
ON DUPLICATE KEY UPDATE name=VALUES(name);

-- Insert sample tags
INSERT INTO tags (name, display_text, description) VALUES
('player_name', '[プレイヤー名]', 'プレイヤーの名前を表示'),
('item_name', '[アイテム名]', 'アイテムの名前を表示'),
('location', '[場所]', '現在の場所を表示')
ON DUPLICATE KEY UPDATE name=VALUES(name);

-- Insert sample forbidden words
INSERT INTO forbidden_words (word, replacement, reason, category) VALUES
('バグ', '不具合', 'より適切な表現', 'technical'),
('ダメ', '良くない', 'より丁寧な表現', 'tone'),
('やばい', '大変', 'より適切な表現', 'tone')
ON DUPLICATE KEY UPDATE word=VALUES(word);
EOF
    
    success "Sample data created"
}

# Setup development tools
setup_dev_tools() {
    log "Setting up development tools..."
    
    cd "$PROJECT_ROOT"
    
    # Setup Git hooks (if .git exists)
    if [[ -d ".git" ]]; then
        # Create pre-commit hook
        cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Run linting before commit
npm run lint
EOF
        chmod +x .git/hooks/pre-commit
        success "Git hooks setup"
    fi
    
    # Create VS Code settings (if .vscode doesn't exist)
    if [[ ! -d ".vscode" ]]; then
        mkdir -p .vscode
        
        cat > .vscode/settings.json << EOF
{
  "typescript.preferences.importModuleSpecifier": "relative",
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  },
  "files.exclude": {
    "node_modules": true,
    ".next": true,
    "build": true
  },
  "search.exclude": {
    "node_modules": true,
    ".next": true,
    "build": true
  }
}
EOF
        
        cat > .vscode/extensions.json << EOF
{
  "recommendations": [
    "bradlc.vscode-tailwindcss",
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
    "ms-vscode.vscode-typescript-next"
  ]
}
EOF
        
        success "VS Code configuration created"
    fi
}

# Start development services
start_services() {
    if [[ "$START_SERVICES" != "true" ]]; then
        warn "Skipping service startup"
        return 0
    fi
    
    log "Starting development server..."
    
    cd "$PROJECT_ROOT"
    
    # Start the development server in the background
    log "Starting Next.js development server..."
    log "Server will be available at http://localhost:3000"
    log "Press Ctrl+C to stop the server"
    
    npm run dev
}

# Show completion message
show_completion() {
    success "Local development setup completed!"
    echo
    log "Next steps:"
    echo "  1. Open http://localhost:3000 in your browser"
    echo "  2. Login with one of the sample accounts:"
    echo "     - admin@example.com (Admin)"
    echo "     - writer@example.com (Scenario Writer)"
    echo "     - translator@example.com (Translator)"
    echo "     - reviewer@example.com (Reviewer)"
    echo "  3. Password for all accounts: 'password'"
    echo
    log "Useful commands:"
    echo "  npm run dev          - Start development server"
    echo "  npm run build        - Build for production"
    echo "  npm run lint         - Run linting"
    echo "  npm test             - Run tests"
    echo
    log "Database information:"
    echo "  Host: ${DB_HOST:-localhost}"
    echo "  Database: ${DB_NAME:-project_forest_dev}"
    echo "  User: ${DB_USER:-root}"
    echo
}

# Main setup function
main() {
    log "Starting Project Forest local development setup"
    
    check_requirements
    install_dependencies
    setup_environment
    setup_database
    setup_dev_tools
    
    if [[ "$START_SERVICES" == "true" ]]; then
        start_services
    else
        show_completion
    fi
}

# Handle script termination
trap 'error "Setup interrupted"' INT TERM

# Parse arguments and run main function
parse_args "$@"
main