output "local_shortener_url" {
  description = "URL for the local shortener API through Nginx."
  value       = "http://localhost:${var.http_port}"
}

output "local_health_url" {
  description = "Health endpoint for the local stack."
  value       = "http://localhost:${var.http_port}/health"
}

output "local_metrics_url" {
  description = "Prometheus metrics endpoint for the local stack."
  value       = "http://localhost:${var.http_port}/metrics"
}

output "local_docker_network" {
  description = "Docker network created for the local platform."
  value       = docker_network.platform.name
}

output "local_container_names" {
  description = "Container names provisioned by the local Docker configuration."
  value = [
    docker_container.nginx.name,
    docker_container.api[0].name,
    docker_container.api[1].name,
    docker_container.postgres.name,
    docker_container.redis.name,
  ]
}

# Example cloud outputs; uncomment with the AWS resources in main.tf.
# output "aws_application_public_ip" {
#   description = "Public IP address of the AWS application host."
#   value       = aws_instance.shortener.public_ip
# }
#
# output "aws_rds_endpoint" {
#   description = "Private RDS PostgreSQL endpoint."
#   value       = aws_db_instance.shortener.address
# }
