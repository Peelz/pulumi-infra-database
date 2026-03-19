"""
MongoDB Atlas Module

Environment-aware configuration for MongoDB Atlas clusters.
Supports dev and prod environments with appropriate sizing and settings.

Prerequisites:
    - MongoDB Atlas Organization ID
    - API keys configured via:
        pulumi config set mongodbatlas:publicKey <public_key>
        pulumi config set --secret mongodbatlas:privateKey <private_key>
"""

import pulumi
import pulumi_mongodbatlas as mongodbatlas

# Environment-specific defaults
ENV_DEFAULTS = {
    "dev": {
        "tier": "M0",  # Free tier
        "provider_name": "TENANT",
        "backing_provider_name": "GCP",
        "cloud_backup": False,
        "auto_scaling_disk_gb_enabled": False,
        "auto_scaling_compute_enabled": False,
    },
    "prod": {
        "tier": "M10",  # Minimum for production features
        "provider_name": "GCP",
        "backing_provider_name": None,
        "cloud_backup": True,
        "auto_scaling_disk_gb_enabled": True,
        "auto_scaling_compute_enabled": True,
    },
}

# Region mapping from GCP to MongoDB Atlas format
GCP_TO_ATLAS_REGION = {
    "asia-southeast1": "ASIA_SOUTHEAST_1",
    "asia-southeast2": "ASIA_SOUTHEAST_2",
    "asia-east1": "ASIA_EAST_1",
    "asia-east2": "ASIA_EAST_2",
    "asia-northeast1": "ASIA_NORTHEAST_1",
    "asia-northeast2": "ASIA_NORTHEAST_2",
    "asia-northeast3": "ASIA_NORTHEAST_3",
    "asia-south1": "ASIA_SOUTH_1",
    "australia-southeast1": "AUSTRALIA_SOUTHEAST_1",
    "europe-west1": "EUROPE_WEST_1",
    "europe-west2": "EUROPE_WEST_2",
    "europe-west3": "EUROPE_WEST_3",
    "europe-west4": "EUROPE_WEST_4",
    "europe-west6": "EUROPE_WEST_6",
    "us-central1": "US_CENTRAL_1",
    "us-east1": "US_EAST_1",
    "us-east4": "US_EAST_4",
    "us-west1": "US_WEST_1",
    "us-west2": "US_WEST_2",
}


def create_mongodb_atlas_cluster(
    name: str,
    config: pulumi.Config,
    environment: str,
) -> dict:
    """
    Create a MongoDB Atlas cluster with database user and IP access.

    Args:
        name: Base name for resources
        config: Pulumi config object
        environment: Environment name (dev/prod)

    Returns:
        Dictionary containing created resources and outputs
    """
    # Get environment defaults
    env_defaults = ENV_DEFAULTS.get(environment, ENV_DEFAULTS["dev"])

    # Required configuration
    org_id = config.require("mongodb_atlas_org_id")

    # Configuration with environment-aware defaults
    gcp_region = (
        config.get("mongodb_region") or config.get("region") or "asia-southeast1"
    )
    atlas_region = GCP_TO_ATLAS_REGION.get(gcp_region, "ASIA_SOUTHEAST_1")

    cluster_tier = config.get("mongodb_tier") or env_defaults["tier"]
    mongo_version = config.get("mongodb_version") or "7.0"

    # Determine provider settings based on tier
    is_free_tier = cluster_tier == "M0"
    provider_name = "TENANT" if is_free_tier else env_defaults["provider_name"]
    backing_provider_name = (
        "GCP" if is_free_tier else env_defaults["backing_provider_name"]
    )

    cloud_backup = config.get_bool("mongodb_backup_enabled")
    if cloud_backup is None:
        cloud_backup = False if is_free_tier else env_defaults["cloud_backup"]

    auto_scaling_disk = config.get_bool("mongodb_auto_scaling_disk")
    if auto_scaling_disk is None:
        auto_scaling_disk = (
            False if is_free_tier else env_defaults["auto_scaling_disk_gb_enabled"]
        )

    # Create Atlas Project
    project = mongodbatlas.Project(
        f"{name}-project",
        name=f"{name}-project",
        org_id=org_id,
    )

    # Create Cluster
    cluster_args = {
        "project_id": project.id,
        "name": f"{name}-cluster",
        "provider_name": provider_name,
        "provider_region_name": atlas_region,
        "provider_instance_size_name": cluster_tier,
        "cluster_type": "REPLICASET",
        "mongo_db_major_version": mongo_version,
        "cloud_backup": cloud_backup,
        "auto_scaling_disk_gb_enabled": auto_scaling_disk,
    }

    # Add backing provider for free tier
    if backing_provider_name:
        cluster_args["backing_provider_name"] = backing_provider_name

    cluster = mongodbatlas.Cluster(
        f"{name}-cluster",
        **cluster_args,
    )

    # Create Database User
    db_password = config.require_secret("mongodb_password")
    db_username = config.get("mongodb_user") or "appuser"
    db_name = config.get("mongodb_db_name") or "appdb"

    database_user = mongodbatlas.DatabaseUser(
        f"{name}-user",
        project_id=project.id,
        username=db_username,
        password=db_password,
        auth_database_name="admin",
        roles=[
            mongodbatlas.DatabaseUserRoleArgs(
                role_name="readWrite",
                database_name=db_name,
            ),
        ],
        labels=[
            mongodbatlas.DatabaseUserLabelArgs(
                key="environment",
                value=environment,
            ),
        ],
    )

    # IP Access List
    # For production, configure specific IPs/CIDR blocks
    # For development, you might allow broader access (not recommended for sensitive data)
    allowed_cidr = config.get("mongodb_allowed_cidr")

    ip_access_list = None
    if allowed_cidr:
        ip_access_list = mongodbatlas.ProjectIpAccessList(
            f"{name}-ip-access",
            project_id=project.id,
            comment=f"Managed by Pulumi - {environment}",
            cidr_block=allowed_cidr,
        )

    result = {
        "project": project,
        "cluster": cluster,
        "database_user": database_user,
        "outputs": {
            "project_id": project.id,
            "cluster_name": cluster.name,
            "connection_string": cluster.connection_strings.apply(
                lambda cs: cs.standard_srv if cs else None
            ),
            "user_name": database_user.username,
        },
    }

    if ip_access_list:
        result["ip_access_list"] = ip_access_list

    return result
