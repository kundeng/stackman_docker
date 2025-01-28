# PostgreSQL 13 with PostGIS Stack

This stack runs PostgreSQL 13 with PostGIS extension, designed to be used by other stacks like Directus.

## Features

- PostgreSQL 13 with PostGIS extension
- Exposed on port 5432
- Accessible via host.docker.internal
- Configurable database name, user, and password
- Data persistence through Docker volumes

## Default Configuration

- Database: directus
- User: sa
- Password: Welcome1
- Host: host.docker.internal
- Port: 5432

## Usage

Other stacks can connect to this database using host.docker.internal:5432
