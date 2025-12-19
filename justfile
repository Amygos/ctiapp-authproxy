# App - Deployment Justfile

set dotenv-load

# Variables
compose_file := "compose.yaml"
compose_prod_file := "compose.prod.yaml"
quadlet_dir := "quadlet"
image_name := "ctiapp-authproxy"
image_tag := "latest"
dockerfile := "Dockerfile"
registry := "ghcr.io/nethesis"
ansible_extra_args := ""

# Colors for output
blue := '\033[0;34m'
green := '\033[0;32m'
yellow := '\033[1;33m'
nc := '\033[0m'

# Show this help message
@help:
    printf "{{blue}}CTI App Auth Proxy - Deployment Justfile{{nc}}\n\n"
    printf "{{green}}Available recipes:{{nc}}\n"
    just --list --unsorted
    printf "\n"

# Development environment recipes

# Build the application container image without cache
@dev-build-no-cache:
    printf "{{blue}}Building container dev images (no cache)...{{nc}}\n"
    podman-compose build --no-cache
    printf "{{green}}Image built successfully!{{nc}}\n"

# Start development environment
@dev-start:
    #!/usr/bin/env bash
    if podman-compose ps | grep -q 'Up'; then
        printf "{{yellow}}Development environment is already running!{{nc}}\n"
        exit 1
    fi
    printf "{{blue}}Starting development environment...{{nc}}\n"
    podman-compose up --build -d
    printf "{{green}}Development environment started!{{nc}}\n"
    printf "HTTP:  http://localhost:8080\n"
    printf "HTTPS: https://localhost:8443\n"

# Stop development environment
@dev-stop:
    printf "{{blue}}Stopping development environment...{{nc}}\n"
    podman-compose down
    printf "{{green}}Development environment stopped!{{nc}}\n"

# Restart development environment
@dev-restart:
    printf "{{blue}}Restarting development environment...{{nc}}\n"
    podman-compose restart
    printf "{{green}}Development environment restarted!{{nc}}\n"

# Show logs from development environment
@dev-logs:
    podman-compose logs -f

# Rebuild from scratch and restart
@dev-rebuild: dev-build-no-cache dev-stop dev-start
    printf "{{green}}Complete rebuild finished!{{nc}}\n"

# Stop and remove all containers, networks, and volumes
@dev-clean:
    printf "{{blue}}Cleaning development environment...{{nc}}\n"
    podman-compose down -v --rmi all --remove-orphans --volumes
    printf "{{green}}Development environment cleaned!{{nc}}\n"

# Get image tags based on git metadata (internal helper)
@_get-tags:
    #!/usr/bin/env bash
    # Get git metadata
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    IS_DEFAULT_BRANCH="false"
    if [[ "$BRANCH" == "main" ]] || [[ "$BRANCH" == "master" ]]; then
        IS_DEFAULT_BRANCH="true"
    fi
    
    # Build tags (matching GitHub Actions metadata-action)
    echo "{{registry}}/{{image_name}}:$BRANCH"
    echo "{{registry}}/{{image_name}}:${BRANCH}-${SHA}"
    
    if [[ "$IS_DEFAULT_BRANCH" == "true" ]]; then
        echo "{{registry}}/{{image_name}}:latest"
    fi

# Build container image with metadata tags (branch, sha, latest)
@build:
    #!/usr/bin/env bash
    printf "{{blue}}Building container image with metadata tags...{{nc}}\n"
    
    # Get git metadata
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    # Get tags
    mapfile -t TAGS < <(just _get-tags)
    
    # Build tag arguments
    TAG_ARGS=""
    for tag in "${TAGS[@]}"; do
        TAG_ARGS="$TAG_ARGS -t $tag"
        printf "  Tag: $tag\n"
    done
    
    # Build with podman (using buildah backend)
    printf "{{blue}}Building image...{{nc}}\n"
    podman build \
        --file {{dockerfile}} \
        --format docker \
        $TAG_ARGS \
        --label "org.opencontainers.image.source=https://github.com/nethesis/ctiapp-authproxy" \
        --label "org.opencontainers.image.revision=$SHA" \
        --label "org.opencontainers.image.version=$BRANCH-$SHA" \
        .
    
    printf "{{green}}Image built successfully!{{nc}}\n"
    printf "{{blue}}Built tags:{{nc}}\n"
    for tag in "${TAGS[@]}"; do
        printf "  • $tag\n"
    done

# Build and push container image to registry (requires authentication)
@build-push: build
    #!/usr/bin/env bash
    printf "{{blue}}Pushing container image to registry...{{nc}}\n"
    
    # Check if logged in to registry
    if ! podman login --get-login {{registry}} >/dev/null 2>&1; then
        printf "{{yellow}}Not logged in to {{registry}}{{nc}}\n"
        printf "{{yellow}}Run: podman login {{registry}}{{nc}}\n"
        exit 1
    fi
    
    # Get tags
    mapfile -t TAGS < <(just _get-tags)
    
    # Push all tags
    printf "{{blue}}Pushing images...{{nc}}\n"
    for tag in "${TAGS[@]}"; do
        printf "{{blue}}Pushing $tag...{{nc}}\n"
        podman push "$tag"
    done
    
    printf "{{green}}Images pushed successfully!{{nc}}\n"
    printf "{{blue}}Pushed tags:{{nc}}\n"
    for tag in "${TAGS[@]}"; do
        printf "  • $tag\n"
    done

# Login to GitHub Container Registry
@registry-login:
    #!/usr/bin/env bash
    printf "{{blue}}Logging in to {{registry}}...{{nc}}\n"
    printf "{{yellow}}You will need a GitHub Personal Access Token with 'write:packages' scope{{nc}}\n"
    printf "{{yellow}}Generate one at: https://github.com/settings/tokens{{nc}}\n\n"
    printf "Enter your GitHub username: "
    read -r USERNAME
    podman login {{registry}} -u "$USERNAME"
    printf "{{green}}Logged in successfully!{{nc}}\n"

# Show current registry login status
@registry-status:
    #!/usr/bin/env bash
    printf "{{blue}}Registry login status:{{nc}}\n"
    if podman login --get-login {{registry}} >/dev/null 2>&1; then
        USERNAME=$(podman login --get-login {{registry}})
        printf "{{green}}✓ Logged in to {{registry}} as $USERNAME{{nc}}\n"
    else
        printf "{{yellow}}✗ Not logged in to {{registry}}{{nc}}\n"
        printf "Run: just registry-login\n"
    fi

# Quadlet generation recipes

# Generate Quadlet files from podman-compose.yml
@quadlet-generate:
    printf "{{blue}}Generating Quadlet files from {{compose_file}}...{{nc}}\n"
    mkdir -p {{quadlet_dir}}
    podman-compose -f {{compose_file}} -f {{compose_prod_file}} config | podlet -f {{quadlet_dir}} --install --absolute-host-paths /home/app compose
    printf "{{green}}Quadlet files generated in {{quadlet_dir}}/{{nc}}\n"
    ls -la {{quadlet_dir}}/

# Remove generated Quadlet files
@quadlet-clean:
    printf "{{blue}}Removing generated Quadlet files...{{nc}}\n"
    find {{quadlet_dir}} -maxdepth 1 -type f \( -name '*.container' -o -name '*.network' -o -name '*.volume' -o -name '*.kube' -o -name '*.pod' \) -delete
    printf "{{green}}Quadlet files removed (overrides preserved)!{{nc}}\n"

# Clean and regenerate Quadlet files
@quadlet-regenerate: quadlet-clean quadlet-generate

# Check configuration and dependencies
@check:
    #!/usr/bin/env bash
    printf "{{blue}}Checking dependencies...{{nc}}\n"
    command -v podman >/dev/null 2>&1 && printf "{{green}}✓ podman installed{{nc}}\n" || printf "{{yellow}}✗ podman not found{{nc}}\n"
    command -v podman-compose >/dev/null 2>&1 && printf "{{green}}✓ podman-compose installed{{nc}}\n" || printf "{{yellow}}✗ podman-compose not found{{nc}}\n"
    command -v podlet >/dev/null 2>&1 && printf "{{green}}✓ podlet installed{{nc}}\n" || printf "{{yellow}}✗ podlet not found{{nc}}\n"
    command -v ansible >/dev/null 2>&1 && printf "{{green}}✓ ansible installed{{nc}}\n" || printf "{{yellow}}✗ ansible not found{{nc}}\n"
    printf "\n"
    printf "{{blue}}Checking configuration files...{{nc}}\n"
    test -f {{compose_file}} && printf "{{green}}✓ {{compose_file}} exists{{nc}}\n" || printf "{{yellow}}✗ {{compose_file}} not found{{nc}}\n"
    test -f {{compose_prod_file}} && printf "{{green}}✓ {{compose_prod_file}} exists{{nc}}\n" || printf "{{yellow}}✗ {{compose_prod_file}} not found{{nc}}\n"
    test -f traefik/config.yml && printf "{{green}}✓ traefik/config.yml exists{{nc}}\n" || printf "{{yellow}}✗ traefik/config.yml not found{{nc}}\n"
    test -f Dockerfile && printf "{{green}}✓ Dockerfile exists{{nc}}\n" || printf "{{yellow}}✗ Dockerfile not found{{nc}}\n"

# Ansible deployment recipes

# Check Ansible playbook syntax
@ansible-check:
    printf "{{blue}}Checking Ansible playbook syntax...{{nc}}\n"
    cd deploy && ansible-playbook deploy.yml --syntax-check
    printf "{{green}}Ansible playbook syntax is valid!{{nc}}\n"

# Lint Ansible playbooks (requires ansible-lint)
@ansible-lint:
    #!/usr/bin/env bash
    printf "{{blue}}Linting Ansible playbooks...{{nc}}\n"
    if ! command -v ansible-lint >/dev/null 2>&1; then
        printf "{{yellow}}ansible-lint not installed. Install with: pip install ansible-lint{{nc}}\n"
        exit 1
    fi
    cd deploy && ansible-lint deploy.yml
    printf "{{green}}Ansible lint completed!{{nc}}\n"

# Run all pre-deployment checks
@deploy-check: check quadlet-generate ansible-check
    printf "{{green}}All checks passed! Ready for deployment.{{nc}}\n"
# Deploy application using Ansible
@deploy:
    #!/usr/bin/env bash
    printf "{{blue}}Starting deployment...{{nc}}\n"
    # Check for APP_HOSTNAME environment variable
    if [ -z "$APP_HOSTNAME" ]; then
        printf "{{yellow}}APP_HOSTNAME environment variable not set!{{nc}}\n"
        exit 1
    fi
    ansible-playbook -i root@"$APP_HOSTNAME", deploy/deploy.yml -e "traefik_hostname=$APP_HOSTNAME" {{ansible_extra_args}}
