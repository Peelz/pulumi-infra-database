# AGENTS.md - AI Assistant Guidelines

**Pulumi Infrastructure-as-Code** project for GCP Cloud SQL PostgreSQL and MongoDB Atlas.
Python-based with environment-aware configurations (dev/prod).

## Project Structure
```
├── __main__.py              # Entry point - service routing and validation
├── cloudsql_postgres.py     # GCP Cloud SQL PostgreSQL module
├── mongodb_atlas.py         # MongoDB Atlas cluster module
├── Justfile                 # Task runner commands
├── Pulumi.yaml              # Project config
├── Pulumi.{service}-{env}.yaml  # Stack configs
└── scripts/onboard.sh       # Bootstrap script for GCS/KMS
```

## Build/Lint/Test Commands

### Setup
```bash
just setup                        # Create venv and install deps
source venv/bin/activate          # Activate venv
```

### Linting (Ruff)
```bash
just lint                         # Check for lint errors
just lint-fix                     # Auto-fix lint errors
just fmt                          # Format code
just fmt-check                    # Check formatting only
```

### Testing (pytest)
```bash
just test                         # Run all tests
just test-verbose                 # Verbose output
just test-file tests/test_foo.py  # Run single file
just test-one tests/test_foo.py test_function  # Run single test
```

### Pulumi Operations
```bash
just select postgresql-dev        # Select stack
just preview                      # Preview changes
just up                           # Deploy
just destroy                      # Tear down
just output                       # View outputs
just stacks                       # List all stacks
```

### Environment Initialization (via Justfile)
```bash
just quickstart-dev <project-id>  # Full dev setup: bucket + KMS + stacks
just quickstart-prod <project-id> # Full prod setup
just dev <project-id>             # Alias for init-dev
just prod <project-id>            # Alias for init-prod
```

## Code Style Guidelines

### Formatting
- **Indentation**: 4 spaces
- **Line length**: 88-100 characters
- **Quotes**: Double quotes `"`
- **Trailing commas**: Yes, on multi-line structures

### Import Organization
```python
# 1. Standard library
import os

# 2. Third-party
import pulumi
from pulumi_gcp import sql

# 3. Local
from cloudsql_postgres import create_postgres_instance
```

### Naming Conventions
| Element   | Convention      | Example                          |
|-----------|-----------------|----------------------------------|
| Files     | snake_case      | `cloudsql_postgres.py`           |
| Functions | snake_case      | `create_postgres_instance()`     |
| Variables | snake_case      | `db_password`, `env_defaults`    |
| Constants | SCREAMING_SNAKE | `ENV_DEFAULTS`                   |

### Type Hints
Always use type hints on function signatures:
```python
def create_postgres_instance(
    name: str,
    config: pulumi.Config,
    environment: str,
) -> dict:
```

### Docstrings (Google Style)
```python
def create_postgres_instance(...) -> dict:
    """
    Create a Cloud SQL PostgreSQL instance with database and user.

    Args:
        name: Base name for resources
        config: Pulumi config object
        environment: Environment name (dev/prod)

    Returns:
        Dictionary containing created resources and outputs
    """
```

### Error Handling
```python
# Validation - fail fast with descriptive messages
if service_type not in valid_services:
    raise ValueError(f"Invalid service_type: {service_type}. Must be one of: {valid_services}")

# Required config - use require() to fail if missing
db_password = config.require_secret("postgres_password")

# Optional config - use get() with fallback
region = config.get("postgres_region") or config.get("region") or "asia-southeast1"

# Boolean config (None-aware)
deletion_protection = config.get_bool("postgres_deletion_protection")
if deletion_protection is None:
    deletion_protection = env_defaults["deletion_protection"]
```

### Environment-Aware Defaults
```python
ENV_DEFAULTS = {
    "dev": {"tier": "db-f1-micro", "deletion_protection": False},
    "prod": {"tier": "db-custom-2-4096", "deletion_protection": True},
}
env_defaults = ENV_DEFAULTS.get(environment, ENV_DEFAULTS["dev"])
```

## Pulumi Patterns

### Resource Naming
```python
instance = sql.DatabaseInstance(f"{name}-instance", ...)
database = sql.Database(f"{name}-db", ...)
```

### Return Structure
```python
return {
    "instance": instance,
    "database": database,
    "outputs": {
        "instance_name": instance.name,
        "connection_name": instance.connection_name,
    },
}
```

### Resource Labels
```python
user_labels={"environment": environment, "managed-by": "pulumi"}
```

## Shell Script Style (scripts/)
- Start with `set -euo pipefail`
- Use functions for logical steps
- UPPERCASE for globals, lowercase for locals
- Color-coded output: `GREEN`, `YELLOW`, `RED`

## Important Notes
- Never commit secrets - use `pulumi config set --secret`
- Always validate inputs before creating resources
- Stack naming: `{service}-{environment}` (e.g., `postgresql-dev`)
- Prefer functional style over classes
