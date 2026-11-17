variable "project_name" {
  description = "Resource-name prefix for the URL Shortener platform."
  type        = string
  default     = "url-shortener"
}

variable "project_root" {
  description = "Absolute or module-relative path to the project root containing Dockerfile and nginx/."
  type        = string
  default     = ".."
}

variable "docker_host" {
  description = "Docker daemon endpoint. Leave empty to use Docker provider defaults/context."
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Tag for the locally built API image."
  type        = string
  default     = "local"
}

variable "nginx_image" {
  description = "Nginx reverse-proxy image."
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "postgres_image" {
  description = "PostgreSQL image for local development."
  type        = string
  default     = "postgres:16-alpine"
}

variable "redis_image" {
  description = "Redis image for local development."
  type        = string
  default     = "redis:7-alpine"
}

variable "http_port" {
  description = "Host port published by the Nginx container."
  type        = number
  default     = 8080
}

variable "public_base_url" {
  description = "Public base URL returned in generated short links."
  type        = string
  default     = "http://localhost:8080"
}

variable "postgres_db" {
  description = "PostgreSQL database name."
  type        = string
  default     = "shortener"
}

variable "postgres_user" {
  description = "PostgreSQL application username."
  type        = string
  default     = "shortener"
}

variable "postgres_password" {
  description = "Local PostgreSQL password; override through a protected tfvars file or TF_VAR_postgres_password."
  type        = string
  sensitive   = true
  default     = "shortener"
}

variable "cache_ttl_seconds" {
  description = "Redis cache lifetime for cached short links."
  type        = number
  default     = 3600
}

# AWS example inputs; these are only referenced in the commented AWS section.
variable "aws_region" {
  description = "AWS region for the portfolio cloud example."
  type        = string
  default     = "us-east-1"
}

variable "aws_vpc_id" {
  description = "Existing VPC ID for the AWS example."
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "aws_public_subnet_id" {
  description = "Public subnet ID for the EC2 application host."
  type        = string
  default     = "subnet-0123456789abcdef0"
}

variable "aws_private_subnet_ids" {
  description = "Private subnet IDs spanning multiple Availability Zones for RDS."
  type        = list(string)
  default     = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
}

variable "aws_admin_cidr" {
  description = "Trusted administrator IPv4 CIDR for SSH; use a narrow CIDR such as a /32."
  type        = string
  default     = "203.0.113.10/32"
}

variable "aws_ami_id" {
  description = "AMI ID for the EC2 host, selected for the configured AWS region."
  type        = string
  default     = "ami-0123456789abcdef0"
}

variable "aws_instance_type" {
  description = "EC2 instance type for the demo application host."
  type        = string
  default     = "t3.small"
}

variable "aws_key_name" {
  description = "Existing EC2 key pair name; prefer SSM Session Manager for production."
  type        = string
  default     = "url-shortener-demo"
}

variable "aws_postgres_engine_version" {
  description = "PostgreSQL engine version supported by the target AWS region."
  type        = string
  default     = "16.3"
}

variable "aws_rds_instance_class" {
  description = "RDS instance class for the portfolio example."
  type        = string
  default     = "db.t3.micro"
}

variable "aws_rds_allocated_storage" {
  description = "RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "aws_rds_password" {
  description = "RDS password; use a secret manager or protected tfvars, never commit it."
  type        = string
  sensitive   = true
  default     = "change-me-before-use"
}

variable "environment" {
  description = "Environment tag for the AWS example."
  type        = string
  default     = "portfolio"
}
