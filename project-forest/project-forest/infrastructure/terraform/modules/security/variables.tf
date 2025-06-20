# Security Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "app_port" {
  description = "Port on which the application runs"
  type        = number
  default     = 3000
}

variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 3000
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 3306
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_management_cidr_blocks" {
  description = "CIDR blocks allowed for database management access"
  type        = list(string)
  default     = []
}

variable "enable_redis" {
  description = "Enable Redis security group"
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Enable Bastion host security group"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}