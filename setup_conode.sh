#!/bin/bash

# Function to check if a package is installed
check_package() {
    dpkg -l "$1" &> /dev/null
}

# Check if Citus is installed
if ! check_package postgresql-15-citus-11.3; then
    echo "Citus is not installed. Adding Citus repository..."
    # Add Citus repository for package manager
    curl https://install.citusdata.com/community/deb.sh | sudo bash
fi

# Check if PostgreSQL is installed
if ! check_package postgresql-15; then
    echo "PostgreSQL is not installed. Installing PostgreSQL..."
    sudo apt-get -y install postgresql-15
fi

# Install Citus and initialize a database
echo "Installing Citus and initializing the database..."
sudo apt-get -y install postgresql-15-citus-11.3

# Preload Citus extension
sudo pg_conftool 15 main set shared_preload_libraries citus

# Define the number of worker nodes
NUM_WORKERS=2

# Define coordinator hostname
COORD_HOST=$(hostname -I | awk '{print $1}')

# Define array for worker hosts and ports
WORKER_HOSTS=()
WORKER_PORTS=()

# Loop to populate worker hosts and ports
for ((i=1; i<=NUM_WORKERS; i++)); do
    WORKER_HOSTS+=("worker-$i")
    WORKER_PORTS+=(5432)  # Update with respective ports for each worker if needed
done

# Step 1: Add worker node information

# Define function to execute SQL commands as the postgres user
execute_sql() {
    sudo -i -u postgres psql -c "$1"
}

# Register the coordinator hostname
execute_sql "SELECT citus_set_coordinator_host('$COORD_HOST', 5432);"

# Add worker nodes
for ((i=0; i<NUM_WORKERS; i++)); do
    execute_sql "SELECT * from citus_add_node('${WORKER_HOSTS[$i]}', ${WORKER_PORTS[$i]});"
done

# Step 2: Verify installation

# Define function to check SQL queries
check_sql() {
    result=$(sudo -i -u postgres psql -tAc "$1")
    echo "$result"
}

# Check if worker nodes are added to the pg_dist_node table
check_result=$(check_sql "SELECT * FROM citus_get_active_worker_nodes();")

# Display result
echo "Active Worker Nodes:"
echo "$check_result"

# Check if Citus installation is successful
if [[ -n "$check_result" ]]; then
    echo "Citus installation succeeded."
else
    echo "Citus installation failed. Please check logs for errors."
    exit 1
fi

# Ready to use Citus
echo "Ready to use Citus. The new Citus database is accessible in psql through the postgres user."
echo "sudo -i -u postgres psql"

