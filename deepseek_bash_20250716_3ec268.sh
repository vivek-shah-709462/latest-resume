#!/bin/bash

# Laravel E-Commerce Cart Setup Script (Idempotent with SQLite Fallback)
# Automates installation with MySQL or SQLite database

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_DIR="ecommerce-cart"
USE_SQLITE=false

# Check database connection
check_db_connection() {
  if [ "$USE_SQLITE" = true ]; then
    return 0
  fi

  echo -e "${YELLOW}Testing MySQL connection...${NC}"
  if mysql -u "$DB_USERNAME" -h "$DB_HOST" -P "$DB_PORT" -e "SELECT 1" &> /dev/null; then
    echo -e "${GREEN}MySQL connection successful${NC}"
    return 0
  else
    echo -e "${RED}MySQL connection failed${NC}"
    return 1
  fi
}

# Initialize SQLite database
init_sqlite() {
  echo -e "${YELLOW}Initializing SQLite database...${NC}"
  DB_DATABASE="$APP_DIR/database/database.sqlite"
  touch "$DB_DATABASE"
  
  # Update .env for SQLite
  sed -i 's/DB_CONNECTION=mysql/DB_CONNECTION=sqlite/' .env
  sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_DATABASE/" .env
  sed -i '/DB_USERNAME=/d' .env
  sed -i '/DB_PASSWORD=/d' .env
  sed -i '/DB_HOST=/d' .env
  sed -i '/DB_PORT=/d' .env
  
  USE_SQLITE=true
}

# Main setup function
setup() {
  # [Previous idempotent steps 1-4 remain exactly the same...]

  # Modified database configuration step
  echo -e "${YELLOW}Configuring database...${NC}"
  DB_HOST="127.0.0.1"
  DB_PORT="3306"
  DB_DATABASE="laravel_cart"
  DB_USERNAME="root"
  DB_PASSWORD=""

  if ! check_db_connection; then
    echo -e "${YELLOW}MySQL not available. Falling back to SQLite...${NC}"
    init_sqlite
  else
    sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=mysql/' .env
    sed -i "s/DB_HOST=.*/DB_HOST=$DB_HOST/" .env
    sed -i "s/DB_PORT=.*/DB_PORT=$DB_PORT/" .env
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_DATABASE/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USERNAME/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
  fi

  # [Rest of the idempotent steps 5-12 remain the same...]
  
  # Final message with DB info
  if [ "$USE_SQLITE" = true ]; then
    echo -e "${GREEN}Using SQLite database at: $DB_DATABASE${NC}"
  else
    echo -e "${GREEN}Using MySQL database: $DB_DATABASE${NC}"
  fi
}

# Run setup
setup