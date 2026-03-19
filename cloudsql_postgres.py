"""
GCP Cloud SQL PostgreSQL Module

Environment-aware configuration for Cloud SQL PostgreSQL instances.
Supports dev and prod environments with appropriate sizing and settings.
"""

import pulumi
from pulumi_gcp import sql

# Environment-specific defaults
ENV_DEFAULTS = {
    "dev": {
        "tier": "db-f1-micro",
        "availability_type": "ZONAL",
        "disk_size": 10,
        "disk_autoresize_limit": 50,
        "backup_retention_days": 3,
        "deletion_protection": False,
        "point_in_time_recovery": False,
    },
    "prod": {
        "tier": "db-custom-2-4096",
        "availability_type": "REGIONAL",
        "disk_size": 50,
        "disk_autoresize_limit": 200,
        "backup_retention_days": 14,
        "deletion_protection": True,
        "point_in_time_recovery": True,
    },
}


def create_postgres_instance(
    name: str,
    config: pulumi.Config,
    environment: str,
) -> dict:
    """
    Create a Cloud SQL PostgreSQL instance with database and user.

    Args:
        name: Base name for resources
        config: Pulumi config object
        environment: Environment name (dev/prod)

    Returns:
        Dictionary containing created resources and outputs
    """
    # Get environment defaults
    env_defaults = ENV_DEFAULTS.get(environment, ENV_DEFAULTS["dev"])

    # Configuration with environment-aware defaults
    region = config.get("postgres_region") or config.get("region") or "asia-southeast1"
    db_tier = config.get("postgres_tier") or env_defaults["tier"]
    db_version = config.get("postgres_version") or "POSTGRES_15"
    availability_type = (
        config.get("postgres_availability") or env_defaults["availability_type"]
    )
    disk_size = config.get_int("postgres_disk_size") or env_defaults["disk_size"]
    disk_autoresize_limit = (
        config.get_int("postgres_disk_autoresize_limit")
        or env_defaults["disk_autoresize_limit"]
    )
    backup_retention_days = (
        config.get_int("postgres_backup_retention")
        or env_defaults["backup_retention_days"]
    )
    deletion_protection = config.get_bool("postgres_deletion_protection")
    if deletion_protection is None:
        deletion_protection = env_defaults["deletion_protection"]
    point_in_time_recovery = config.get_bool("postgres_point_in_time_recovery")
    if point_in_time_recovery is None:
        point_in_time_recovery = env_defaults["point_in_time_recovery"]

    # Create Cloud SQL PostgreSQL instance
    instance = sql.DatabaseInstance(
        f"{name}-instance",
        database_version=db_version,
        region=region,
        deletion_protection=deletion_protection,
        settings=sql.DatabaseInstanceSettingsArgs(
            tier=db_tier,
            availability_type=availability_type,
            disk_size=disk_size,
            disk_type="PD_SSD",
            disk_autoresize=True,
            disk_autoresize_limit=disk_autoresize_limit,
            backup_configuration=sql.DatabaseInstanceSettingsBackupConfigurationArgs(
                enabled=True,
                start_time="02:00",  # UTC
                point_in_time_recovery_enabled=point_in_time_recovery,
                transaction_log_retention_days=7 if point_in_time_recovery else 1,
                backup_retention_settings=sql.DatabaseInstanceSettingsBackupConfigurationBackupRetentionSettingsArgs(
                    retained_backups=backup_retention_days,
                    retention_unit="COUNT",
                ),
            ),
            ip_configuration=sql.DatabaseInstanceSettingsIpConfigurationArgs(
                ipv4_enabled=config.get_bool("postgres_public_ip") or False,
                private_network=config.get("postgres_private_network"),
                require_ssl=True,
                authorized_networks=[],
            ),
            maintenance_window=sql.DatabaseInstanceSettingsMaintenanceWindowArgs(
                day=7,  # Sunday
                hour=3,  # 3 AM UTC
                update_track="stable",
            ),
            database_flags=[
                sql.DatabaseInstanceSettingsDatabaseFlagArgs(
                    name="log_checkpoints",
                    value="on",
                ),
                sql.DatabaseInstanceSettingsDatabaseFlagArgs(
                    name="log_connections",
                    value="on",
                ),
                sql.DatabaseInstanceSettingsDatabaseFlagArgs(
                    name="log_disconnections",
                    value="on",
                ),
                sql.DatabaseInstanceSettingsDatabaseFlagArgs(
                    name="log_lock_waits",
                    value="on",
                ),
            ],
            user_labels={
                "environment": environment,
                "managed-by": "pulumi",
            },
        ),
    )

    # Create database
    db_name = config.get("postgres_db_name") or "appdb"
    database = sql.Database(
        f"{name}-db",
        instance=instance.name,
        name=db_name,
        charset="UTF8",
        collation="en_US.UTF8",
    )

    # Create user
    db_password = config.require_secret("postgres_password")
    db_username = config.get("postgres_user") or "appuser"

    user = sql.User(
        f"{name}-user",
        instance=instance.name,
        name=db_username,
        password=db_password,
    )

    return {
        "instance": instance,
        "database": database,
        "user": user,
        "outputs": {
            "instance_name": instance.name,
            "connection_name": instance.connection_name,
            "public_ip": instance.public_ip_address,
            "private_ip": instance.private_ip_address,
            "database_name": database.name,
            "user_name": user.name,
        },
    }
