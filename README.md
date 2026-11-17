# Cloud-Native URL Shortener & Analytics Platform

A portfolio-grade URL shortening and click analytics service built to demonstrate practical cloud-native, DevOps, SRE, and DevSecOps patterns. The platform combines a FastAPI application, PostgreSQL persistence, Redis caching, Nginx load balancing, Prometheus metrics, Grafana dashboards, Terraform infrastructure as code, and GitHub Actions delivery to GHCR.

> **Status:** Portfolio/reference project. Review defaults, pin images and dependencies, configure production secrets, and perform security and reliability reviews before production use.

## Project Overview & Key Features

- Create short links with optional custom codes and HTTP(S) URL validation.
- Redirect short codes and record click counts in PostgreSQL.
- Cache frequently used destinations in Redis.
- Serve two API replicas behind an Nginx reverse proxy/load balancer.
- Expose `/health` and Prometheus `/metrics` endpoints.
- Track request count, status code, latency histogram, and redirect totals.
- Scrape FastAPI, Redis, and PostgreSQL metrics with Prometheus exporters.
- Provision the Grafana Prometheus datasource and overview dashboard automatically.
- Run the API in a multi-stage Docker image as a non-root user.
- Manage a local Docker deployment with Terraform and include a commented AWS EC2/RDS example.
- Run lint, unit-test, image security scan, and GHCR publishing jobs through GitHub Actions.

## Architecture

```text
                         ┌─────────────────────┐
                         │      Browser/API     │
                         └──────────┬──────────┘
                                    │ HTTP :8080
                         ┌──────────▼──────────┐
                         │ Nginx reverse proxy │
                         │  load balancing     │
                         └───────┬───────┬─────┘
                                 │       │
                    ┌────────────▼─┐   ┌─▼────────────┐
                    │ FastAPI API 1│   │FastAPI API 2 │
                    │ :8000 /metrics│  │:8000 /metrics│
                    └──────┬───┬───┘   └──┬───┬───────┘
                           │   │          │   │
                    ┌──────▼┐ ┌▼──────────▼┐ ┌▼────────┐
                    │ Redis │ │ PostgreSQL  │ │         │
                    │ Cache │ │ Link + clicks│ │         │
                    └───┬───┘ └──────┬─────┘ └─────────┘
                        │            │
                 ┌──────▼────────────▼─────┐
                 │ Redis / Postgres Exporters│
                 └──────────────┬───────────┘
                                │ metrics
                         ┌──────▼──────────┐
                         │   Prometheus    │
                         │ :9090           │
                         └──────┬──────────┘
                                │ PromQL
                         ┌──────▼──────────┐
                         │     Grafana     │
                         │ :3000 Dashboard │
                         └─────────────────┘
```

All services share a private Docker bridge network. Host-published ports are Nginx, Prometheus, and Grafana. PostgreSQL and Redis are not published to the host by default.

## Technology Stack

| Area | Technology |
| --- | --- |
| API | Python, FastAPI, SQLAlchemy async |
| Persistence | PostgreSQL |
| Cache | Redis |
| Edge routing | Nginx |
| Metrics and dashboards | Prometheus, Grafana, Redis Exporter, Postgres Exporter |
| Containers | Docker, Docker Compose |
| Infrastructure as code | Terraform Docker provider; commented AWS example |
| CI/CD and security | GitHub Actions, Black, Flake8, pytest, Trivy, GHCR |

## Prerequisites

- Docker Engine and Docker Compose plugin, or Docker Desktop.
- Git for cloning the repository.
- Terraform CLI and a running Docker daemon only when using the Terraform local configuration.

## Run with Docker Compose

1. Clone the repository and enter the project directory:

   ```bash
   git clone https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPOSITORY>.git
   cd <YOUR_REPOSITORY>
   ```

2. Create a local environment file and change the example passwords:

   ```bash
   cp .env.example .env
   ```

   On PowerShell, use `Copy-Item .env.example .env`. Do not commit `.env`.

3. Start the platform:

   ```bash
   docker compose up --pull always --build -d
   ```

4. Open the services:

   - Shortener API through Nginx: `http://localhost:8080`
   - API health: `http://localhost:8080/health`
   - Prometheus metrics: `http://localhost:8080/metrics`
   - Prometheus UI: `http://localhost:9090`
   - Grafana: `http://localhost:3000` (credentials from `.env`)
   - Interactive API schema: `http://localhost:8080/docs`

5. Create a short link:

   ```bash
   curl -X POST http://localhost:8080/api/v1/links \
     -H 'Content-Type: application/json' \
     -d '{"url":"https://www.example.com","custom_code":"demo1"}'
   ```

   Follow the returned `short_url` to test redirection. Click analytics are available at `GET /api/v1/links/{code}/analytics`.

6. Stop the stack when finished:

   ```bash
   docker compose down
   ```

   Named volumes are retained. To delete persistent data as well, use `docker compose down -v` with care.

## Monitoring

Grafana provisions the Prometheus datasource and **URL Shortener - Service Overview** dashboard on startup. The dashboard includes:

- HTTP request rate by route.
- p50 and p95 request latency.
- 4xx and 5xx response ratios.
- Prometheus scrape status for API replicas and monitoring targets.
- Redis/PostgreSQL availability.
- Short-link redirect rate.

The dashboard is backed by application request counters and latency histograms, plus Redis and PostgreSQL exporters. Prometheus retains metrics for 15 days in the default Compose configuration.

## Terraform

The `terraform/` directory contains a local Docker configuration that creates a bridge network, PostgreSQL and Redis named volumes, the API image, two API containers, PostgreSQL, Redis, and Nginx.

1. Ensure Docker is running and change directory:

   ```bash
   cd terraform
   ```

2. Initialize the Docker provider:

   ```bash
   terraform init
   ```

3. Review the proposed infrastructure changes:

   ```bash
   terraform plan
   ```

4. Apply only after reviewing the plan and configuring local credentials/secrets appropriately:

   ```bash
   terraform apply
   ```

The AWS example in `terraform/main.tf` is commented out and is **not provisioned** by the default configuration. It illustrates EC2, security groups, and private RDS PostgreSQL resources and requires real VPC/subnet/AMI values, provider setup, and secure secret management. Do not use placeholder defaults or broadly open administrative ingress in a real account. Terraform state can contain secrets; protect it and use a remote encrypted backend for shared environments.

## CI/CD Pipeline

Install local quality and test tools with `python -m pip install -r requirements-dev.txt`. The workflow at `.github/workflows/ci-cd.yml` runs on pushes, pull requests, tags, and manual dispatch:

1. Installs application and quality-check dependencies.
2. Checks formatting with Black and lint with Flake8.
3. Runs the pytest suite.
4. Builds the Docker image and scans OS/library vulnerabilities with Trivy; high and critical findings fail the job.
5. On non-PR events, authenticates with the built-in `GITHUB_TOKEN` and pushes branch, tag, commit-SHA, and default-branch `latest` tags to GHCR.

Ensure the repository allows GitHub Actions to write packages. Images are published under `ghcr.io/<OWNER>/<REPOSITORY>`.

## Screenshots


### Grafana Dashboard

![Grafana URL Shortener overview dashboard](docs/images/grafana-dashboard.png)

### GitHub Actions CI/CD Pipeline

![GitHub Actions CI/CD workflow](docs/images/github-actions-pipeline.png)

## Repository Layout

```text
.
├── .github/workflows/ci-cd.yml
├── app/                       # FastAPI application and Python dependencies
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/                # Provisioning and dashboard JSON
├── nginx/nginx.conf
├── terraform/                  # Local Docker IaC and commented AWS example
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

## Security Notes

- Replace all example passwords before exposing services beyond a local machine.
- Never commit `.env`, access tokens, cloud credentials, or Terraform state.
- The Compose file publishes Prometheus and Grafana ports for local inspection; restrict access with firewall rules or remove host mappings in shared environments.
- Use a secrets manager, TLS, least-privilege identities, immutable image tags, image signing, and a reviewed vulnerability policy for production.
- CI runs the committed metrics unit tests; expand the suite as API behavior evolves.

## License

Choose and add a license file before redistributing this project. Until then, no license is specified.
