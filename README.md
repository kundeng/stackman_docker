# Stack Manager README

## Overview

The Stack Manager script helps you manage multiple stack environments by facilitating initialization, environment variable merging, Docker Compose file rendering, and managing stack deployment lifecycles. The Stack Manager provides commands for creating stack templates, merging environment variables, building and running stacks, and stopping them.

### Why Use Shell Instead of Taskfile?

The Stack Manager script is implemented in shell rather than using other tools like Taskfile due to a specific bug in Taskfile's shell implementation. This bug affects the handling of associative arrays, making it necessary to use external shell scripting for reliability. Additionally, using shell provides greater flexibility for environment management tasks.

### Prerequisite: Gomplate

The `gomplate` templating tool is required for rendering configuration files. Please ensure it is installed before using the Stack Manager.

### Why This Setup?

This setup allows for stack-specific customization, which often includes the need for templating environment variables and configuration files. The Stack Manager ensures that common and stack-specific settings can be easily managed and applied across different environments.

## Commands and Usage

### Initialization

The `init` command initializes the environment setup by creating necessary directories, configuration files, and templates.

```sh
./stackman.sh init
```

- **Prompts**:
  - Application data directory (default: `app_data`).
  - Stacks directory (default: `stacks`).
- **Creates**:
  - `app.conf`: Configuration file containing `APP_DIR` and `STACKS_DIR` paths.
  - `.gitignore`: Configured to ignore runtime directories (`APP_DIR` and `STACKS_DIR`).
  - `global.env`: Global environment variables template.
  - `.stackignore`: File to ignore certain stacks during operations.
  - `docker-compose.yml.tmpl`: Default Docker Compose template for creating stack-specific configurations.

### Creating Stack Templates

The `create_template` command generates a prototype directory in `STACKS_DIR` for a stack. The user can manually modify this directory before deployment.

```sh
./stackman.sh create_template -s <STACK>
```

- **Creates**:
  - Stack-specific design template directory in `STACKS_DIR`.
  - Template files such as `.env.tmpl`, `docker-compose.yml.tmpl`, `.gitignore`, and `README.md`.

### Environment Merging Logic

The `merge` command merges `global.env` variables into each stack's `.env` file.

```sh
./stackman.sh merge -s <STACK>
```

#### Process

1. **Global Variables**: Reads all key-value pairs in `global.env` into an associative array, `global_vars`, excluding comments and empty lines.
2. **Existing Stack Variables**: Reads each line of the stack's `.env` file (`OUTPUT_ENV`) into an array, `env_lines`.
3. **Backup**: If `.env` exists and `--force` is set, a backup (`.env.backup`) is created.
4. **Merge Process**:
   - **Global Variables Addition**: Appends all key-value pairs from `global.env` to the top of the new `.env`, marking them as global.
   - **Stack-Specific Variables**: Iterates through `env_lines`, preserving stack-specific entries. If a key in `.env` exists in `global.env`, it is commented out with `#` and noted as "Existed in global.env."

#### Limitations

- **No Nested Variable Expansion**: Variables in `global.env` that reference others (e.g., `DOMAIN2=$DOMAIN`) are not expanded.
- **Duplicate Keys**: If `global.env` and the stack `.env` file share keys, the stack’s `.env` version is retained and commented out.
- **No Live Updates**: The merged `.env` file is static and reflects the state at merge time. Changes in `global.env` require re-running `merge` for updates.

### Build Process

The `build` command creates or updates the Docker Compose configuration (`docker-compose.yml`) and other stack-specific template files based on `global.env` and each stack's `.env`.

```sh
./stackman.sh build -s <STACK>
```

#### Build Steps

1. **Environment Merge**: Runs the `merge` command to ensure the latest global and stack-specific environment variables are present in the stack’s `.env` file.
2. **Docker Compose Rendering**:
   - Checks if `docker-compose.yml.tmpl` exists in the stack directory.
   - If it exists and `docker-compose.yml` does not, it uses `gomplate` to render `docker-compose.yml` from `docker-compose.yml.tmpl`, substituting variables defined in `.env`.
   - The output file, `docker-compose.yml`, contains resolved variables for Docker Compose to use directly.
3. **Data Template Rendering**:
   - If a `data.tmpl` directory exists, each `.tmpl` file within it is processed individually.
   - `gomplate` renders each `.tmpl` file, outputting the result into a `data` directory with the same filename but without the `.tmpl` extension.
   - Variable substitution is based on values in `.env`.
4. **Force Option**:
   - When `--force` is specified, it overwrites any existing `docker-compose.yml` and rendered files in `data/`.

#### Limitations

- **Static Rendering**: Files are rendered at build time, so changes in `.env` or `global.env` require re-running `build` to update `docker-compose.yml` and data templates.
- **Missing Templates**: If no `.env` or template files are present, `build` generates nothing but completes without errors, requiring correct setup beforehand.
- **Gomplate Not Tested**: The use of `gomplate` for rendering has not been thoroughly tested in all use cases.

### Running and Stopping Stacks

- **Run a Stack**: Starts the Docker Compose services for a specific stack or all stacks that are not ignored.

  ```sh
  ./stackman.sh run -s <STACK>
  ```
- **Stop a Stack**: Stops the running services for a specific stack or all stacks.

  ```sh
  ./stackman.sh stop -s <STACK>
  ```

### Ignoring Stacks

The `ignore` command adds a stack to `.stackignore`, ensuring that it is ignored in future operations like `merge`, `build`, `run`, or `stop`.

```sh
./stackman.sh ignore -s <STACK>
```

### Listing Stacks

The `list` command lists all runtime stacks in `APP_DIR`, indicating whether each stack is ignored or not.

```sh
./stackman.sh list
```

## Summary of Commands

- **`init`**: Initializes directories, configuration files, and templates.
- **`create_template`**: Creates a prototype stack directory in `STACKS_DIR`.
- **`merge`**: Merges global environment variables into each stack’s `.env` file.
- **`build`**: Builds Docker Compose and other templates based on merged environment variables.
- **`run`**: Starts Docker Compose services for one or all stacks.
- **`stop`**: Stops running Docker Compose services.
- **`ignore`**: Adds a stack to `.stackignore` to be ignored in operations.
- **`list`**: Lists all stacks in `APP_DIR` and their ignore status.

## Example Usage

```sh
# Initialize environment
./stackman.sh init

# Create a new stack template
./stackman.sh create_template -s my_stack

# Merge environment variables
./stackman.sh merge -s my_stack

# Build the stack
./stackman.sh build -s my_stack

# Run the stack
./stackman.sh run -s my_stack

# Stop the stack
./stackman.sh stop -s my_stack

# Ignore the stack
./stackman.sh ignore -s my_stack

# List all stacks
./stackman.sh list
```

## Limitations and Future Improvements

- **Proxy Implementation**:
  - Implement a proxy setup with Authentik, Traefik, and Whoami to handle authentication and reverse proxy needs effectively.
- **Per-Stack Customization**:
  - Implement per-stack customization using a Taskfile for managing stack-specific actions.
  - **Shell Script for Workaround**: The customization logic uses a shell script instead of a Taskfile due to a bug with associative arrays in Taskfile's Go shell, making shell scripting a more reliable choice for this functionality.
- **Static Environment Files**:
  - The `.env` files can be modified manually and are dynamic in that sense. However, changes in `global.env` or the need for additional flexibility may require re-running `merge` or other commands to propagate updates.
- **Gomplate Not Tested**:
  - The use of `gomplate` for rendering templates has not been extensively tested and may need further validation in different environments.

## Working Notes

### add this for external network for proxying.

```
networks:
  network1:
    external: true
    name: "${NETWORK_ID}"
```
