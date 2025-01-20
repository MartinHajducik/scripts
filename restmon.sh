#!/bin/bash

# Base64-encoded username:password (use echo "username:password" | base64 to generate this)
AUTH_CREDENTIALS="dXNlcm5hbWU6cGFzc3dvcmQ="

# Function to get CPU usage
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'
}

# Function to get memory usage
get_memory_usage() {
    free | grep Mem | awk '{print $3/$2 * 100.0}'
}

# Function to get disk usage
get_disk_usage() {
    df -h / | grep / | awk '{print $5}' | sed 's/%//g'
}

# Function to get detailed service status
get_service_status() {
    local service_name=$1
    local is_active=$(systemctl is-active $service_name)
    local is_enabled=$(systemctl is-enabled $service_name 2>/dev/null)
    local start_time=""
    local exit_time=""

    if [ "$is_active" == "active" ]; then
        start_time=$(systemctl show $service_name --property=ActiveEnterTimestamp | cut -d= -f2)
    fi

    if [ "$is_active" == "failed" ]; then
        exit_time=$(systemctl show $service_name --property=InactiveExitTimestamp | cut -d= -f2)
    fi

    echo -e "\"$service_name\": {\"service_status\": \"$is_active\", \"service_enabled\": \"$is_enabled\", \"start_time\": \"$start_time\", \"exit_time\": \"$exit_time\"}"
}

# Function to parse query parameters and get services status
get_services_status() {
    local query_string=$1
    local services=$(echo "$query_string" | awk -F'=' '{print $2}' | tr ',' ' ')
    local service_statuses=""

    for service in $services; do
        if [ -n "$service_statuses" ]; then
            service_statuses="$service_statuses, $(get_service_status $service)"
        else
            service_statuses="$(get_service_status $service)"
        fi
    done

    echo "{$service_statuses}"
}

# Function to check Basic Authentication
check_auth() {
    local auth_header=$1
    if [ "$auth_header" != "Authorization: Basic $AUTH_CREDENTIALS" ]; then
        echo "HTTP/1.1 401 Unauthorized"
        echo "WWW-Authenticate: Basic realm=\"Restricted Area\""
        echo
        echo "Unauthorized"
        return 1
    fi
    return 0
}

# Start a simple HTTP server using netcat
while true; do
    request=$(nc -l -p 8080 -q 1)
    auth_header=$(echo "$request" | grep "Authorization")

    if ! check_auth "$auth_header"; then
        continue
    fi

    query_string=$(echo "$request" | grep "GET" | awk '{print $2}' | sed 's/\/\?//')

    if [[ $query_string == services* ]]; then
        response_body=$(get_services_status $query_string)
    else
        response_body=$(cat <<EOF
        {
            "cpu_usage": "$(get_cpu_usage)",
            "memory_usage": "$(get_memory_usage)",
            "disk_usage": "$(get_disk_usage)"
        }
EOF
        )
    fi

    echo -e "HTTP/1.1 200 OK\nContent-Type: application/json\n\n$response_body" | nc -l -p 8080 -q 1
done
