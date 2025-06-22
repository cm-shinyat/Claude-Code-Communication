#!/bin/bash
# Local pre-build script to ensure dependencies are available

set -e

echo "🔧 Preparing for offline Docker build..."

# Ensure dependencies are installed locally
if [ ! -d "node_modules" ] || [ ! -f "node_modules/.package-lock.json" ]; then
    echo "📦 Installing dependencies locally..."
    npm install --no-audit --no-fund
fi

echo "🏗️  Building Docker image with local dependencies..."
docker build -f infrastructure/docker/Dockerfile.offline -t project-forest:latest .

echo "✅ Build completed with local dependencies!"