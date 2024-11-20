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

# Check if API exists in Tyk
check_api_exists() {
    local tyk_host=$1
    local tyk_token=$2
    local api_name=$3
    local api_listen_path=$4
    local api_target_url=$5
    local response
    
    response=$(curl -X GET -k -s "$tyk_host/api/apis?p=-1" \
        -H "Authorization: $tyk_token")
    
    echo "$response" | jq -e --arg name "$api_name" --arg target_url "$api_target_url" --arg listen_path "$api_listen_path" \
        '.apis[] | select(.api_definition.name == $name and .api_definition.proxy.target_url == $target_url and .api_definition.proxy.listen_path == $listen_path)' >/dev/null
    
    return $?
}

# API migration function
migrate_apis() {
    local tyk_host=$1
    local tyk_token=$2
    local migrate_count=0
    local skip_count=0

    # Export all published APIs
    apictl export apis --format json -e "$WSO2_ENV_NAME"

    for file_path in "$WSO2_EXPORT_PATH"/*.zip; do
        local file_name=$(basename "$file_path")
        
        # Extract archive path and swagger
        local archive_path
        archive_path="${file_name/_/-}"     
        archive_path="${archive_path/_*}" 
        local swagger=$(unzip -p "$file_path" "$archive_path"/Definitions/swagger.json)

        local title=$(echo "$swagger" | jq -r '.info.title')
        local version=$(echo "$swagger" | jq -r '.info.version')

        # Extract swagger data
        local base_path=$(echo "$swagger" | jq -r '."x-wso2-basePath"')
        local base_path_encoded=$(echo "$base_path" | jq -R -r -s '@uri')
        local production_endpoint=$(echo "$swagger" | jq -r '."x-wso2-production-endpoints".urls[0]')
        local production_endpoint_encoded=$(echo "$production_endpoint" | jq -R -r -s '@uri')
        
        # Check if API already exists
        if check_api_exists "$tyk_host" "$tyk_token" "$title" "$base_path" "$production_endpoint"; then
            log_info "Skipping existing API: $title v$version"
            ((skip_count++))
            continue
        fi

        # Check for localhost in endpoint
        if echo "$production_endpoint" | grep -qi "localhost"; then
            log_warning "API '$title' v$version uses localhost in endpoint: $production_endpoint"
            log_warning "This may cause connectivity issues in the target environment"
        fi

        # Import API to Tyk
        local import_response
        import_response=$(curl -X POST -k -s "$tyk_host/api/apis/oas/import?listenPath={$base_path_encoded}&upstreamURL=${production_endpoint_encoded}" \
            -H "Authorization: $tyk_token" \
            -H "Content-Type: application/json" \
            -d "$swagger")
        
        local import_status
        import_status=$(echo "$import_response" | jq -r '.Status')

        if [[ "$import_status" == "OK" ]]; then
            log_info "Migrated $title v$version"
            ((migrate_count++))
        else
            log_error "Could not migrate $title: $(echo "$import_response" | jq -r '.Message')"
        fi        
    done

    log_info "Migration complete - $migrate_count APIs migrated, $skip_count APIs skipped"
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