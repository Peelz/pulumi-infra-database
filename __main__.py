"""
GCP Cloud SQL PostgreSQL & MongoDB Atlas Pulumi Program

This is a multi-service, multi-environment template.
The stack name pattern is: {service}-{env} (e.g., postgresql-dev, mongodb-prod)

Configuration:
    - service_type: "postgresql" or "mongodb"
    - environment: "dev" or "prod"
"""

import pulumi

from cloudsql_postgres import create_postgres_instance
from mongodb_atlas import create_mongodb_atlas_cluster

# Configuration
config = pulumi.Config()

# Required: Service type determines which infrastructure to deploy
service_type = config.require("service_type")  # postgresql or mongodb

# Required: Environment determines sizing and configuration
environment = config.require("environment")  # dev or prod

# Optional: Base name for resources (defaults to service-env pattern)
base_name = config.get("base_name") or f"{service_type}-{environment}"

# Validate service_type
valid_services = ["postgresql", "mongodb"]
if service_type not in valid_services:
    raise ValueError(
        f"Invalid service_type: {service_type}. Must be one of: {valid_services}"
    )

# Validate environment
valid_environments = ["dev", "prod"]
if environment not in valid_environments:
    raise ValueError(
        f"Invalid environment: {environment}. Must be one of: {valid_environments}"
    )

# Export common metadata
pulumi.export("service_type", service_type)
pulumi.export("environment", environment)
pulumi.export("base_name", base_name)

# Deploy based on service type
if service_type == "postgresql":
    postgres = create_postgres_instance(base_name, config, environment)

    # Export PostgreSQL outputs
    pulumi.export("postgres_instance_name", postgres["outputs"]["instance_name"])
    pulumi.export("postgres_connection_name", postgres["outputs"]["connection_name"])
    pulumi.export("postgres_public_ip", postgres["outputs"]["public_ip"])
    pulumi.export("postgres_private_ip", postgres["outputs"]["private_ip"])
    pulumi.export("postgres_database_name", postgres["outputs"]["database_name"])
    pulumi.export("postgres_user_name", postgres["outputs"]["user_name"])

elif service_type == "mongodb":
    mongodb = create_mongodb_atlas_cluster(base_name, config, environment)

    # Export MongoDB outputs
    pulumi.export("mongodb_project_id", mongodb["outputs"]["project_id"])
    pulumi.export("mongodb_cluster_name", mongodb["outputs"]["cluster_name"])
    pulumi.export("mongodb_connection_string", mongodb["outputs"]["connection_string"])
    pulumi.export("mongodb_user_name", mongodb["outputs"]["user_name"])
