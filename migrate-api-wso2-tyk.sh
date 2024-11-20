#!/usr/bin/env bash

# Strict mode for better error handling and safety
set -euo pipefail

# Constants
readonly SCRIPT_NAME=$(basename "$0")
readonly WSO2_ENV_NAME="wso2-to-tyk-migration"
readonly REQUIRED_TOOLS=("apictl" "curl" "jq")
readonly WSO2_EXPORT_PATH=~/.wso2apictl/exported/migration/"$WSO2_ENV_NAME"/tenant-default/apis
readonly MINIMUM_APICTL_VERSION="4.4.0"

# Logging functions
log_error() {
    echo "ERROR: $*" >&2
}

log_info() {
    echo "INFO: $*"
}

log_warning() {
    echo "WARNING: $*"
}

# Version comparison function
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -C -V
}

# Check apictl version compatibility
check_apictl_version() {
    local current_version
    current_version=$(apictl version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

    if ! version_ge "$current_version" "$MINIMUM_APICTL_VERSION"; then
        log_error "Incompatible apictl version"
        log_error "Current version: $current_version"
        log_error "Minimum required version: $MINIMUM_APICTL_VERSION"
        exit 1
    fi

    log_info "Apictl version check passed (${current_version})"
}

# Input validation
validate_inputs() {
    if [[ $# -ne 5 ]]; then
        log_error "Incorrect number of arguments"
        echo "Usage: $SCRIPT_NAME <wso2_host> <wso2_username> <wso2_password> <tyk_host> <tyk_token>"
        exit 1
    fi
}

# Prerequisite checks
check_prerequisites() {
    local missing_tools=()

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    check_apictl_version
}

# WSO2 environment setup
setup_wso2_environment() {
    local wso2_host=$1
    local wso2_username=$2
    local wso2_password=$3
    local wso2_envs=$(apictl get envs)
    
    # Check and manage migration environment
    if echo "$wso2_envs" | grep -q "$WSO2_ENV_NAME"; then
        local existing_host
        existing_host=$(echo "$wso2_envs" | grep "$WSO2_ENV_NAME" | awk '{print $2}')
        
        if [[ "$existing_host" != "$wso2_host" ]]; then
            log_warning "WSO2 migration environment already exists with host: $existing_host"
            log_warning "New host to be configured: $wso2_host"
            
            read -p "Do you want to recreate the environment with the new host? (y/n): " answer
            
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                log_info "Removing existing environment..."
                apictl remove env "$WSO2_ENV_NAME"
                
                log_info "Creating WSO2 environment $WSO2_ENV_NAME with new host"
                apictl add env "$WSO2_ENV_NAME" --apim "$wso2_host"
            else
                log_error "Operation cancelled by user. Exiting..."
                exit 1
            fi
        else
            log_info "Using existing WSO2 environment $WSO2_ENV_NAME"
        fi
    else
        log_info "Creating WSO2 environment $WSO2_ENV_NAME"
        apictl add env "$WSO2_ENV_NAME" --apim "$wso2_host"
    fi
    
    # Login to environment
    echo "$wso2_password" | apictl login "$WSO2_ENV_NAME" -u "$wso2_username" -k --password-stdin
    
    # Clear any existing data from export directory
    rm -f $WSO2_EXPORT_PATH/*
}

# Tyk environment validation
validate_tyk_environment() {
    local tyk_host=$1
    local tyk_token=$2

    local status_code
    status_code=$(curl -k -o /dev/null -s -w "%{http_code}" -H "Authorization: $tyk_token" "$tyk_host/api/apis")
    
    if [ "$status_code" -ne 200 ]; then
        log_error "Could not connect to Tyk Dashboard"
        exit 1
    fi

    log_info "Connected to Tyk dashboard successfully"
}

# API migration function
migrate_apis() {
    local tyk_host=$1
    local tyk_token=$2

    apictl export apis --format json -e "$WSO2_ENV_NAME"

    local migrate_count=0
    
    for file_path in "$WSO2_EXPORT_PATH"/*.zip; do
        local file_name
        file_name=$(basename "$file_path")
        
        # Extract archive path and swagger
        local archive_path
        archive_path="${file_name/_/-}"     
        archive_path="${archive_path/_*}" 
        local swagger
        swagger=$(unzip -p "$file_path" "$archive_path"/Definitions/swagger.json)

        local title
        title=$(echo "$swagger" | jq -r '.info.title')

        # Extract override data
        local base_path
        base_path=$(echo "$swagger" | jq -r '."x-wso2-basePath" | @uri')
        local production_endpoint
        production_endpoint=$(echo "$swagger" | jq -r '."x-wso2-production-endpoints".urls[0] | @uri')

        # Import API to Tyk
        local import_response
        import_response=$(curl -X POST -k -s "$tyk_host/api/apis/oas/import?listenPath={$base_path}&upstreamURL=${production_endpoint}" \
            -H "Authorization: $tyk_token" \
            -H "Content-Type: application/json" \
            -d "$swagger")
        
        local import_status
        import_status=$(echo "$import_response" | jq -r '.Status')

        if [[ "$import_status" == "OK" ]]; then
            log_info "Migrated $title"
            ((migrate_count++))
        else
            log_error "Could not migrate $title: $(echo "$import_response" | jq -r '.Message')"
        fi        
    done

    log_info "Migration complete - $migrate_count APIs migrated"
}

# Main script execution
main() {
    validate_inputs "$@"
    check_prerequisites
    setup_wso2_environment "$1" "$2" "$3"
    validate_tyk_environment "$4" "$5"
    migrate_apis "$4" "$5"
}

# Call main with all script arguments
main "$@"