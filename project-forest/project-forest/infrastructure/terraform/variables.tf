# Project Forest Terraform Variables - ECS/Fargate Configuration

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "project-forest"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_high_availability" {
  description = "Enable high availability with multiple AZs"
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (disable for cost savings in development)"
  type        = bool
  default     = false
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution"
  type        = bool
  default     = false
}

# ECS Configuration
variable "app_image" {
  description = "Docker image for the application"
  type        = string
  default     = "node:18-alpine"  # Placeholder - should be replaced with actual image
}

variable "app_port" {
  description = "Port on which the application runs"
  type        = number
  default     = 3000
}

variable "ecs_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.ecs_cpu)
    error_message = "ECS CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "ecs_memory" {
  description = "Memory (MB) for ECS task"
  type        = number
  default     = 512
  validation {
    condition = (
      (var.ecs_cpu == 256 && contains([512, 1024, 2048], var.ecs_memory)) ||
      (var.ecs_cpu == 512 && var.ecs_memory >= 1024 && var.ecs_memory <= 4096) ||
      (var.ecs_cpu == 1024 && var.ecs_memory >= 2048 && var.ecs_memory <= 8192) ||
      (var.ecs_cpu == 2048 && var.ecs_memory >= 4096 && var.ecs_memory <= 16384) ||
      (var.ecs_cpu == 4096 && var.ecs_memory >= 8192 && var.ecs_memory <= 30720)
    )
    error_message = "ECS memory must be compatible with the specified CPU units."
  }
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch logs retention in days"
  type        = number
  default     = 7
}

# RDS Configuration
variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance (GB)"
  type        = number
  default     = 20
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "project_forest"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

# Development vs Production Presets
locals {
  # Development preset
  dev_config = {
    enable_high_availability    = false
    enable_nat_gateway         = false
    enable_cloudfront          = false
    enable_container_insights  = false
    ecs_cpu                   = 256
    ecs_memory                = 512
    ecs_desired_count         = 1
    db_instance_class         = "db.t3.micro"
    db_allocated_storage      = 20
    log_retention_days        = 3
  }

  # Staging preset
  staging_config = {
    enable_high_availability    = true
    enable_nat_gateway         = true
    enable_cloudfront          = false
    enable_container_insights  = true
    ecs_cpu                   = 512
    ecs_memory                = 1024
    ecs_desired_count         = 1
    db_instance_class         = "db.t3.micro"
    db_allocated_storage      = 20
    log_retention_days        = 7
  }

  # Production preset
  prod_config = {
    enable_high_availability    = true
    enable_nat_gateway         = true
    enable_cloudfront          = true
    enable_container_insights  = true
    ecs_cpu                   = 1024
    ecs_memory                = 2048
    ecs_desired_count         = 2
    db_instance_class         = "db.t3.small"
    db_allocated_storage      = 100
    log_retention_days        = 30
  }

  # Select configuration based on environment
  config = var.environment == "production" ? local.prod_config : (
    var.environment == "staging" ? local.staging_config : local.dev_config
  )
}

# Override variables with environment-specific defaults
variable "auto_configure_environment" {
  description = "Automatically configure settings based on environment"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}