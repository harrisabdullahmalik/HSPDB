#!/bin/bash

# Function to check if a package is installed
check_package() {
    dpkg -l "$1" &> /dev/null
}

# Function to check if a file exists
check_file() {
    [ -f "$1" ]
}

# Function to check if a service is running
check_service() {
    sudo systemctl is-active --quiet "$1"
}

# Step 1: Add Citus repository
if ! check_file "/etc/apt/sources.list.d/citusdata-community.list"; then
    echo "Adding Citus repository..."
    curl https://install.citusdata.com/community/deb.sh | sudo bash
fi

# Step 2: Install PostgreSQL + Citus and initialize a database
if ! check_package "postgresql-15-citus-11.3"; then
    echo "Installing PostgreSQL + Citus..."
    sudo apt-get -y install postgresql-15-citus-11.3

    # Preload Citus extension
    echo "Preloading Citus extension..."
    sudo pg_conftool 15 main set shared_preload_libraries citus
fi

# Step 3: Configure connection and authentication
echo "Configuring connection and authentication..."
sudo pg_conftool 15 main set listen_addresses '*'

# Update pg_hba.conf for unrestricted access from local network
if ! grep -q "10.0.0.0/8" "/etc/postgresql/15/main/pg_hba.conf"; then
    sudo tee -a /etc/postgresql/15/main/pg_hba.conf <<EOF
# Allow unrestricted access to nodes in the local network
host    all             all             10.0.0.0/8              trust

# Also allow the host unrestricted access to connect to itself
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
EOF
fi

# Step 4: Start database servers and enable automatic startup
echo "Starting database server..."
sudo service postgresql restart

if ! check_service "postgresql"; then
    echo "Failed to start PostgreSQL service. Exiting."
    exit 1
fi

echo "Enabling automatic startup for PostgreSQL..."
sudo update-rc.d postgresql enable

# Create Citus extension
echo "Creating Citus extension..."
sudo -i -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS citus;"

# Check if Citus installation is successful
check_citus_extension=$(sudo -i -u postgres psql -tAc "SELECT * FROM pg_extension WHERE extname='citus';")
if [[ -n "$check_citus_extension" ]]; then
    echo "Citus setup completed successfully."
else
    echo "Citus setup failed. Please check logs for errors."
    exit 1
fi

