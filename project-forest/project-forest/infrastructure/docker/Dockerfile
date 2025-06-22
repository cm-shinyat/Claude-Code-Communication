# Project Forest - Robust Dockerfile
# Network error resistant build with retries and fallbacks

FROM node:18-alpine
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache libc6-compat curl

# Configure npm for reliability
RUN npm config set registry https://registry.npmjs.org/ && \
    npm config set fetch-timeout 60000 && \
    npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000

# Copy package files
COPY package*.json ./

# Install with retries and fallbacks
RUN npm ci --prefer-offline --no-audit --no-fund || \
    npm install --prefer-offline --no-audit --no-fund || \
    (npm cache clean --force && npm install --no-audit --no-fund)

# Copy source code
COPY . .

# Build application
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build || exit 1

# Clean up after build
RUN npm prune --production && \
    npm cache clean --force && \
    rm -rf /tmp/* /var/cache/apk/*

# Setup runtime user and directories
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001 && \
    mkdir -p logs uploads && \
    chown -R nextjs:nodejs /app

USER nextjs
EXPOSE 3000

CMD ["npm", "start"]