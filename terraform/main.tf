terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

# -----------------------------------------------------------------------------
# Local development: Docker Network, persistent Volumes, and all application
# containers. Terraform builds the same API Dockerfile used by docker-compose.
# -----------------------------------------------------------------------------

resource "docker_network" "platform" {
  name   = "${var.project_name}_backend"
  driver = "bridge"
}

resource "docker_volume" "postgres_data" {
  name = "${var.project_name}_postgres_data"
}

resource "docker_volume" "redis_data" {
  name = "${var.project_name}_redis_data"
}

resource "docker_image" "api" {
  name = "${var.project_name}-api:${var.image_tag}"

  build {
    context    = var.project_root
    dockerfile = "Dockerfile"
  }
}

resource "docker_image" "nginx" {
  name         = var.nginx_image
  keep_locally = true
}

resource "docker_image" "postgres" {
  name         = var.postgres_image
  keep_locally = true
}

resource "docker_image" "redis" {
  name         = var.redis_image
  keep_locally = true
}

resource "docker_container" "postgres" {
  name  = "${var.project_name}-postgres"
  image = docker_image.postgres.image_id

  env = [
    "POSTGRES_DB=${var.postgres_db}",
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_PASSWORD=${var.postgres_password}",
  ]

  mounts {
    target = "/var/lib/postgresql/data"
    source = docker_volume.postgres_data.name
    type   = "volume"
  }

  networks_advanced {
    name = docker_network.platform.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }

  restart = "unless-stopped"
}

resource "docker_container" "redis" {
  name  = "${var.project_name}-redis"
  image = docker_image.redis.image_id
  command = [
    "redis-server",
    "--appendonly",
    "yes",
  ]

  mounts {
    target = "/data"
    source = docker_volume.redis_data.name
    type   = "volume"
  }

  networks_advanced {
    name = docker_network.platform.name
  }

  healthcheck {
    test     = ["CMD", "redis-cli", "ping"]
    interval = "10s"
    timeout  = "3s"
    retries  = 5
  }

  restart = "unless-stopped"
}

resource "docker_container" "api" {
  count = 2

  name  = "${var.project_name}-api-${count.index + 1}"
  image = docker_image.api.image_id

  env = [
    "DATABASE_URL=postgresql+asyncpg://${var.postgres_user}:${var.postgres_password}@${docker_container.postgres.name}:5432/${var.postgres_db}",
    "REDIS_URL=redis://${docker_container.redis.name}:6379/0",
    "PUBLIC_BASE_URL=${var.public_base_url}",
    "CACHE_TTL_SECONDS=${var.cache_ttl_seconds}",
  ]

  networks_advanced {
    name = docker_network.platform.name
  }

  healthcheck {
    test     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
    interval = "15s"
    timeout  = "3s"
    retries  = 3
  }

  restart    = "unless-stopped"
  depends_on = [docker_container.postgres, docker_container.redis]
}

resource "docker_container" "nginx" {
  name  = "${var.project_name}-nginx"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = var.http_port
  }

  mounts {
    target    = "/etc/nginx/nginx.conf"
    source    = "${var.project_root}/nginx/nginx.conf"
    type      = "bind"
    read_only = true
  }

  networks_advanced {
    name = docker_network.platform.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/health || exit 1"]
    interval = "15s"
    timeout  = "3s"
    retries  = 3
  }

  restart    = "unless-stopped"
  depends_on = [docker_container.api]
}

# -----------------------------------------------------------------------------
# AWS portfolio example (intentionally commented out; not provisioned).
# Design: public EC2 host for the Docker/Nginx edge; private RDS PostgreSQL
# instance in isolated subnets. For production, add private networking, NAT or
# SSM access, TLS/ALB, IAM roles, encryption, backups, and secrets management.
# Uncomment and configure the AWS provider, VPC/subnets, and variables before use.
# -----------------------------------------------------------------------------

# provider "aws" {
#   region = var.aws_region
# }
#
# resource "aws_security_group" "shortener_ec2" {
#   name        = "${var.project_name}-ec2"
#   description = "Public HTTP ingress; restrict SSH to an operator CIDR."
#   vpc_id      = var.aws_vpc_id
#
#   ingress {
#     description = "HTTP to Nginx reverse proxy"
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
#   ingress {
#     description = "SSH administration; set aws_admin_cidr to a trusted /32."
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = [var.aws_admin_cidr]
#   }
#
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }
#
# resource "aws_security_group" "shortener_rds" {
#   name        = "${var.project_name}-rds"
#   description = "Allow PostgreSQL only from the application EC2 security group."
#   vpc_id      = var.aws_vpc_id
#
#   ingress {
#     description     = "PostgreSQL from application host"
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.shortener_ec2.id]
#   }
# }
#
# resource "aws_instance" "shortener" {
#   ami                         = var.aws_ami_id
#   instance_type               = var.aws_instance_type
#   subnet_id                   = var.aws_public_subnet_id
#   vpc_security_group_ids      = [aws_security_group.shortener_ec2.id]
#   associate_public_ip_address = true
#   key_name                    = var.aws_key_name
#
#   tags = {
#     Name        = "${var.project_name}-host"
#     Environment = var.environment
#     ManagedBy   = "Terraform"
#   }
# }
#
# resource "aws_db_subnet_group" "shortener" {
#   name       = "${var.project_name}-db-subnets"
#   subnet_ids = var.aws_private_subnet_ids
#   tags       = { Name = "${var.project_name}-db-subnets" }
# }
#
# resource "aws_db_instance" "shortener" {
#   identifier              = "${var.project_name}-postgres"
#   engine                  = "postgres"
#   engine_version          = var.aws_postgres_engine_version
#   instance_class          = var.aws_rds_instance_class
#   allocated_storage       = var.aws_rds_allocated_storage
#   db_name                 = var.postgres_db
#   username                = var.postgres_user
#   password                = var.aws_rds_password
#   db_subnet_group_name    = aws_db_subnet_group.shortener.name
#   vpc_security_group_ids  = [aws_security_group.shortener_rds.id]
#   publicly_accessible     = false
#   storage_encrypted       = true
#   backup_retention_period = 7
#   skip_final_snapshot     = true # Set false and configure a final snapshot for production.
#   deletion_protection     = false # Enable for production workloads.
#
#   tags = {
#     Name        = "${var.project_name}-postgres"
#     Environment = var.environment
#     ManagedBy   = "Terraform"
#   }
# }
