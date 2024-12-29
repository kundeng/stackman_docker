#!/usr/bin/env bash

set -e  # Exit immediately if a command exits with a non-zero status

# Default values
FORCE="false"
STACK=""
COMMAND=""
CONFIG_FILE="app.conf"
DO_STAGE="false"

# Embedded Template Contents

# Template for app.conf
CONFIG_TEMPLATE_CONTENT=$(cat <<'EOF'
# Configuration File for Stack Manager
APP_DIR='${APP_DIR}'
STACKS_DIR='${STACKS_DIR}'
EOF
)

# Template for global.env
GLOBAL_ENV_TEMPLATE_CONTENT=$(cat <<'EOF'
# Global Environment Variables
DOMAIN=${DOMAIN}
APP_DIR=${APP_DIR}
PROXY_NETWORK=proxy
TZ=America/Detroit
EOF
)

# Template for .stackignore
STACKIGNORE_TEMPLATE_CONTENT=$(cat <<'EOF'
# Stack Ignore File

# List stack names to ignore, one per line
# Example:
# ignored_stack
EOF
)

# Template for docker-compose.yml.tmpl
DOCKER_TEMPLATE_CONTENT=$(cat <<'EOF'
version: "3.3"

services:
  ###############################################
  ####              EXAMPLE                 #####
  ###############################################
  EXAMPLE:
    image: EXAMPLE/EXAMPLE
    container_name: EXAMPLE
    restart: unless-stopped
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.EXAMPLE-secured.rule=Host(EXAMPLE.${DOMAIN})"
      - "traefik.http.routers.EXAMPLE-secured.entrypoints=websecure"
      - "traefik.http.routers.EXAMPLE-secured.tls.certresolver=mytlschallenge"
      - "traefik.http.routers.EXAMPLE-secured.middlewares=authelia"
      - "traefik.http.routers.EXAMPLE-secured.service=EXAMPLE-service"
      - "traefik.http.services.EXAMPLE-service.loadbalancer.server.port=80"

networks:
  proxy:
    external: true
    name: ${PROXY_NETWORK:-proxy}
EOF
)

# Template for .env.tmpl
ENV_TEMPLATE_CONTENT=$(cat <<'EOF'
DOMAIN=${DOMAIN}
STACK=${STACK}
DATA_DIR=${STACK}/data
FIELD1=custom_value
EOF
)

# Template for .gitignore
GITIGNORE_CONTENT=$(cat <<'EOF'
# Stack Management
EOF
)

# Template for .gitignore in stack template directory
GITIGNORE_TEMPLATE_CONTENT=$(cat <<'EOF'
# Ignore environment and data
.env
data
data/*
EOF
)

# Function to load configuration
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  else
    echo "ERROR: Configuration file '$CONFIG_FILE' not found. Please run 'init' first."
    exit 1
  fi
}

# Display help
show_help() {
  echo "Usage: $0 <COMMAND> [OPTIONS]"
  echo ""
  echo "Commands:"
  echo "  init                Initialize environment setup"
  echo "  create_template     Create a new stack template in STACKS_DIR"
  echo "  merge_env           Merge global.env into a stack's .env file"
  echo "  build               Build a stack by merging env and rendering templates"
  echo "  run                 Start a stack or all stacks"
  echo "  stop                Stop a stack or all stacks"
  echo "  ignore              Add a stack to .stackignore"
  echo "  list                List all stacks and their ignore status"
  echo ""
  echo "Options:"
  echo "  -s, --stack <STACK> Specify the stack name (optional; defaults to all stacks if omitted)"
  echo "  -f, --force         Force overwrite existing files where applicable"
  echo "  -h, --help          Show this help message"
  echo "  --stage             Stage the stack after building using Taskfile.yml"
  echo ""
  echo "Example usage:"
  echo "  $0 init"
  echo "  $0 create_template -s my_stack"
  echo "  $0 build -f"
  echo "  $0 build --stage"
  echo "  $0 run"
}

# Function to list all stacks and indicate ignore status
list_stacks() {
  load_config
  if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: Application data directory '$APP_DIR' does not exist. Please run 'init' first."
    exit 1
  fi

  echo "Listing all stacks and their ignore status:"
  for stack_dir in "$APP_DIR"/*/; do
    if [ -d "$stack_dir" ]; then
      stack_name="$(basename "$stack_dir")"
      if grep -Fxq "$stack_name" "$APP_DIR/.stackignore"; then
        echo "[$stack_name]: Ignored"
      else
        echo "[$stack_name]: Not Ignored"
      fi
    fi
  done
}

# Initialize environment files
init() {
  echo "Initializing environment..."

  # Prompt for APP_DIR with default "var"
  read -p "Enter the runtime app and data directory [var]: " user_app_dir
  APP_DIR0="${user_app_dir:-var}"

  # Ensure APP_DIR exists and set to absolute path
  mkdir -p "$APP_DIR0"
  APP_DIR=$(cd "$APP_DIR0" && pwd)
  RUNTIME_STACKS_DIR="$APP_DIR/stacks"
  mkdir -p "$RUNTIME_STACKS_DIR"

  # Prompt for STACKS_DIR with default "stacks"
  read -p "Enter the stacks directory [stacks]: " user_stacks_dir
  STACKS_DIR="${user_stacks_dir:-stacks}"

  # Prompt for DOMAIN
  read -p "Enter the domain: " DOMAIN

  # Write APP_DIR and STACKS_DIR to config file
  echo "Creating configuration file '$CONFIG_FILE'..."
  echo "$CONFIG_TEMPLATE_CONTENT" | sed "s|\${APP_DIR}|$APP_DIR|" | sed "s|\${STACKS_DIR}|$STACKS_DIR|" > "$CONFIG_FILE"
  echo "Configuration saved to '$CONFIG_FILE'."

  # .gitignore setup
  if [ ! -f ".gitignore" ]; then
    echo "Creating .gitignore..."
    echo "$GITIGNORE_CONTENT" > .gitignore
    echo "$APP_DIR0/" >> .gitignore
    echo ".gitignore created with default entries."
  else
    # Ensure APP_DIR and STACKS_DIR are ignored
    if ! grep -Fxq "$APP_DIR0/" ".gitignore"; then
      echo "$APP_DIR0/" >> .gitignore
      echo "Added '$APP_DIR0/' to .gitignore."
    fi
  fi

  # Ensure STACKS_DIR exists
  if [ ! -d "$STACKS_DIR" ]; then
    echo "Creating stacks directory '$STACKS_DIR'..."
    mkdir -p "$STACKS_DIR"
  else
    echo "Stacks directory '$STACKS_DIR' already exists."
  fi

  # Render global.env from embedded template
  echo "Creating 'global.env' in '$APP_DIR'..."
  echo "$GLOBAL_ENV_TEMPLATE_CONTENT" | sed "s|\${APP_DIR}|$APP_DIR|" | sed "s|\${DOMAIN}|$DOMAIN|" > "$APP_DIR/global.env"
  echo "'$APP_DIR/global.env' created from template."

  # Render .stackignore from embedded template
  echo "Creating '.stackignore' in '$APP_DIR'..."
  echo "$STACKIGNORE_TEMPLATE_CONTENT" > "$APP_DIR/.stackignore"
  echo "'$APP_DIR/.stackignore' created from template."

  # Render docker-compose.yml.tmpl in STACKS_DIR (design-time template)
  if [ ! -f "$STACKS_DIR/docker-compose.yml.tmpl" ]; then
    echo "Creating global 'docker-compose.yml.tmpl' in '$STACKS_DIR'..."
    echo "$DOCKER_TEMPLATE_CONTENT" > "$STACKS_DIR/docker-compose.yml.tmpl"
    echo "Global 'docker-compose.yml.tmpl' created in '$STACKS_DIR'."
  else
    echo "Global 'docker-compose.yml.tmpl' already exists in '$STACKS_DIR'."
  fi

  echo "Initialization complete."
}

# Create a new stack template in STACKS_DIR
create_stack_template() {
  load_config

  if [ -z "$STACK" ]; then
    echo "ERROR: --stack option is required for create_template command."
    exit 1
  fi

  DESIGN_STACK_DIR="$STACKS_DIR/$STACK"

  if [ -d "$DESIGN_STACK_DIR" ]; then
    echo "ERROR: Design-time stack template '$DESIGN_STACK_DIR' already exists."
    exit 1
  else
    echo "Creating design-time stack template directory '$DESIGN_STACK_DIR'..."
    mkdir -p "$DESIGN_STACK_DIR/data.tmpl"

    # Copy global docker-compose.yml.tmpl to stack template directory
    cp "$STACKS_DIR/docker-compose.yml.tmpl" "$DESIGN_STACK_DIR/docker-compose.yml.tmpl"

    # Create .env.tmpl in stack template directory
    echo "$ENV_TEMPLATE_CONTENT" | sed "s|\${STACK}|$STACK|" > "$DESIGN_STACK_DIR/.env.tmpl"
    

    # Initialize .gitignore in stack template directory
    echo "$GITIGNORE_TEMPLATE_CONTENT" > "$DESIGN_STACK_DIR/.gitignore"

    # Initialize README.md in stack template directory
    echo "# $STACK Design Template" > "$DESIGN_STACK_DIR/README.md"

    echo "Design-time stack template '$STACK' created successfully in '$DESIGN_STACK_DIR'."
    echo "You can now manually craft the stack template in this directory."
  fi
}

# Merge global.env into a stack's .env
merge_env() {
  load_config
  RUNTIME_STACKS_DIR="$APP_DIR/stacks"

  if [ -z "$STACK" ]; then
    # Run for all stacks if no specific stack is provided
    for stack_dir in "$RUNTIME_STACKS_DIR"/*/; do
      if [ -d "$stack_dir" ]; then
        stack_name="$(basename "$stack_dir")"
        if ! grep -Fxq "$stack_name" "$APP_DIR/.stackignore"; then
          STACK="$stack_name"
          merge_env_single "$RUNTIME_STACKS_DIR/$STACK"
        fi
      fi
    done
  else
    merge_env_single "$RUNTIME_STACKS_DIR/$STACK"
  fi
}

merge_env_single() {
  RUNTIME_STACK_DIR="$1"
  STACK_ENV_TEMPLATE="$STACKS_DIR/$STACK/.env.tmpl"
  OUTPUT_ENV="$RUNTIME_STACK_DIR/.env"
  BACKUP_ENV="$RUNTIME_STACK_DIR/.env.backup"

  if [ ! -d "$RUNTIME_STACK_DIR" ]; then
    echo "Creating runtime stack directory '$RUNTIME_STACK_DIR'..."
    mkdir -p "$RUNTIME_STACK_DIR"
  fi

  if [ ! -f "$APP_DIR/global.env" ]; then
    echo "ERROR: '$APP_DIR/global.env' does not exist. Run init first."
    exit 1
  fi

  if [ ! -f "$STACK_ENV_TEMPLATE" ]; then
    echo "ERROR: Design-time stack template '$STACK_ENV_TEMPLATE' does not exist. Creating default .env file."
    echo "$ENV_TEMPLATE_CONTENT" | sed "s|\${APP_DIR}|$APP_DIR|" | sed "s|\${STACK}|$STACK|" > "$OUTPUT_ENV"
    echo "'$OUTPUT_ENV' created from default stack .env template."
  else
    if [ ! -f "$OUTPUT_ENV" ]; then
      echo "Creating '$OUTPUT_ENV' from template..."
      # Replace placeholders in .env.tmpl
      sed "s|\${DATA_DIR}|$APP_DIR/data|" "$STACK_ENV_TEMPLATE" > "$OUTPUT_ENV"
      echo "'$OUTPUT_ENV' created from template."
    fi
  fi

  if [ "$FORCE" = "true" ] && [ -f "$OUTPUT_ENV" ] && [ ! -f "$BACKUP_ENV" ]; then
    echo "Creating backup of existing .env at '$BACKUP_ENV'..."
    cp "$OUTPUT_ENV" "$BACKUP_ENV"
    echo "Backup created."
  fi

  # Read global.env into an associative array
  declare -A global_vars
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue
    global_vars["$key"]="$value"
  done < "$APP_DIR/global.env"

  # Read stack's .env into an array
  mapfile -t env_lines < "$OUTPUT_ENV"

  # Create a temporary file
  temp_env=$(mktemp)

  echo "# Global environment variables" > "$temp_env"
  for key in "${!global_vars[@]}"; do
    echo "$key=${global_vars[$key]}" >> "$temp_env"
  done
  echo "" >> "$temp_env"

  echo "# Stack-specific environment variables" >> "$temp_env"
  for line in "${env_lines[@]}"; do
    if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]]; then
      echo "$line" >> "$temp_env"
      continue
    fi

    key=$(echo "$line" | cut -d '=' -f1 | xargs)
    if [[ -n "${global_vars[$key]}" ]]; then
      echo "# $line # Existed in global.env" >> "$temp_env"
    else
      echo "$line" >> "$temp_env"
    fi
  done

  mv "$temp_env" "$OUTPUT_ENV"
  echo "Merged .env generated successfully for stack '$STACK'."
}

# Build a stack by merging the env and rendering templates
build() {
  load_config
  RUNTIME_STACKS_DIR="$APP_DIR/stacks"  
  if [ -z "$STACK" ]; then
    for stack_dir in "RUNTIME_STACKS_DIR"/*/; do
      if [ -d "$stack_dir" ]; then
        stack_name="$(basename "$stack_dir")"
        if ! grep -Fxq "$stack_name" "$APP_DIR/.stackignore"; then
          STACK="$stack_name"
          prepare_and_build_stack "$RUNTIME_STACKS_DIR/$STACK"
        fi
      fi
    done
  else
    prepare_and_build_stack "$RUNTIME_STACKS_DIR/$STACK"
  fi
}

prepare_and_build_stack() {
  
  RUNTIME_STACK_DIR="$1"
  DESIGN_STACK_DIR="$STACKS_DIR/$STACK"

  merge_env_single "$RUNTIME_STACK_DIR"



  # Render docker-compose.yml template if it exists
  if [ -f "$DESIGN_STACK_DIR/docker-compose.yml.tmpl" ]; then
    if [ ! -f "$RUNTIME_STACK_DIR/docker-compose.yml" ] || [ "$FORCE" = "true" ]; then
      gomplate --missing-key default -f "$DESIGN_STACK_DIR/docker-compose.yml.tmpl" -o "$RUNTIME_STACK_DIR/docker-compose.yml" -c .=file://"$RUNTIME_STACK_DIR"/.env
      echo "Rendered docker-compose.yml for stack '$STACK'."
    fi
  fi

  # Handle non-template files (e.g., .gitignore, Dockerfile, etc.)
  find "$DESIGN_STACK_DIR" -type f ! -name "*.tmpl" | while read -r regular_file; do
    relative_path="${regular_file#"$DESIGN_STACK_DIR"/}"
    dest_file="$RUNTIME_STACK_DIR/$relative_path"
    dest_dir=$(dirname "$dest_file")

    mkdir -p "$dest_dir"

    # Copy the non-template file if it doesn't exist or FORCE flag is set
    if [ ! -f "$dest_file" ] || [ "$FORCE" = "true" ]; then
        cp "$regular_file" "$dest_file"
        echo "Copied $dest_file."
    fi
  done

  if [ "$DO_STAGE" = "true" ]; then
    stage_stack "$RUNTIME_STACK_DIR"
  fi

  # Render files in data.tmpl directory recursively
  if [ -d "$DESIGN_STACK_DIR/data.tmpl" ]; then
    mkdir -p "$RUNTIME_STACK_DIR/data"
    find "$DESIGN_STACK_DIR/data.tmpl" -type f | while read -r tmpl_file; do
      relative_path="${tmpl_file#"$DESIGN_STACK_DIR"/data.tmpl/}"
      dest_file="$RUNTIME_STACK_DIR/data/${relative_path%.tmpl}"  # Strip the .tmpl suffix
      dest_dir=$(dirname "$dest_file")


      mkdir -p "$dest_dir"

      if [ ! -f "$dest_file" ] || [ "$FORCE" = "true" ]; then
        gomplate --missing-key default -f "$tmpl_file" -o "$dest_file" -c .=file://"$RUNTIME_STACK_DIR"/.env
        echo "Rendered $dest_file."
      fi
    done
  fi
}

stage_stack() {
  RUNTIME_STACK_DIR="$1"
  
  if [ -f "$RUNTIME_STACK_DIR/Taskfile.yml" ]; then
    pushd "$RUNTIME_STACK_DIR" > /dev/null || { echo "ERROR: Failed to navigate to '$RUNTIME_STACK_DIR'."; exit 1; }
    
    if [ "$FORCE" = "true" ]; then
      task stage FORCE=true
    else
      task stage
    fi
    
    popd > /dev/null
    echo "Staged stack '$STACK' using Taskfile."
  else
    echo "No Taskfile.yml found for stack '$STACK', skipping staging phase."
  fi
}


# Run a stack or all stacks
run() {
  load_config
  RUNTIME_STACKS_DIR="$APP_DIR/stacks"  
  if [ -z "$STACK" ]; then
    for stack_dir in "$RUNTIME_STACK_DIR"/*/; do
      if [ -d "$stack_dir" ]; then
        stack_name="$(basename "$stack_dir")"
        if ! grep -Fxq "$stack_name" "$APP_DIR/.stackignore"; then
          STACK="$stack_name"
          run_stack "$RUNTIME_STACKS_DIR/$STACK"
        fi
      fi
    done
  else
    run_stack "$RUNTIME_STACKS_DIR/$STACK"
  fi
}

run_stack(){
  RUNTIME_STACK_DIR="$1"

  if [ -f "$RUNTIME_STACK_DIR/docker-compose.yml" ] || [ -f "$RUNTIME_STACK_DIR/compose.yml" ]; then
    pushd "$RUNTIME_STACK_DIR" > /dev/null || { echo "ERROR: Failed to navigate to '$RUNTIME_STACK_DIR'."; exit 1; }
    
    if [ -f "docker-compose.yml" ]; then
      docker-compose up -d --remove-orphans
    else
      docker compose up -d 
    fi
    
    echo "Started stack '$STACK'."
    popd > /dev/null  # Return to the previous directory
  else
    echo "ERROR: Neither '$RUNTIME_STACK_DIR/docker-compose.yml' nor '$RUNTIME_STACK_DIR/compose.yml' found. Run build first."
    exit 1
  fi
}

# Stop a stack or all stacks
stop() {
  load_config
  RUNTIME_STACKS_DIR="$APP_DIR/stacks"
  if [ -z "$STACK" ]; then
    for stack_dir in "$RUNTIME_STACKS_DIR"/*/; do
      if [ -d "$stack_dir" ]; then
        stack_name="$(basename "$stack_dir")"
        if ! grep -Fxq "$stack_name" "$APP_DIR/.stackignore"; then
          STACK="$stack_name"
          stop_stack "$RUNTIME_STACKS_DIR/$STACK"
        fi
      fi
    done
  else
    stop_stack "$RUNTIME_STACKS_DIR/$STACK"
  fi
}

stop_stack() {
  RUNTIME_STACK_DIR=$1

  if [ -f "$RUNTIME_STACK_DIR/docker-compose.yml" ] || [ -f "$RUNTIME_STACK_DIR/compose.yml" ]; then
    pushd "$RUNTIME_STACK_DIR" > /dev/null || { echo "ERROR: Failed to navigate to '$RUNTIME_STACK_DIR'."; exit 1; }
    
    if [ -f "docker-compose.yml" ]; then
      docker-compose down --remove-orphans 
    else
      docker compose down --remove-orphans
    fi
    
    echo "Stopped stack '$STACK'."
    popd > /dev/null
  else
    echo "ERROR: Neither '$RUNTIME_STACK_DIR/docker-compose.yml' nor '$RUNTIME_STACK_DIR/compose.yml' found."
    exit 1
  fi
}

# Add a stack to the ignore list
ignore_stack() {
  load_config

  if [ -z "$STACK" ]; then
    echo "ERROR: --stack option is required for ignore command."
    exit 1
  fi

  if ! grep -Fxq "$STACK" "$APP_DIR/.stackignore"; then
    echo "$STACK" >> "$APP_DIR/.stackignore"
    echo "Stack '$STACK' added to .stackignore."
  else
    echo "Stack '$STACK' is already in .stackignore."
  fi
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    init|create_template|merge_env|build|run|stop|ignore|list|stage)
      COMMAND="$1"
      shift
      ;;
    -s|--stack)
      STACK="$2"
      shift 2
      ;;
    --stage)
      DO_STAGE="true"
      shift
      ;;
    -f|--force)
      FORCE="true"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Execute the specified command
case "$COMMAND" in
  init)
    init
    ;;
  create_template)
    create_stack_template
    ;;
  merge_env)
    merge_env
    ;;
  build)
    build
    ;;
  run)
    run
    ;;
  stop)
    stop
    ;;
  ignore)
    ignore_stack
    ;;
  list)
    list_stacks
    ;;
  *)
    echo "ERROR: A valid command is required."
    show_help
    exit 1
    ;;
esac
