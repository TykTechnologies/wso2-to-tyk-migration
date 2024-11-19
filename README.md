# WSO2 to Tyk API Migration Bash Script

## Overview

This Bash script streamlines the migration of APIs from WSO2 API Manager to Tyk API Gateway, automating the transfer of API configurations between the two platforms.

## Prerequisites

The script uses the following tools. Make sure they are available before running the script.

- WSO2 API Manager: Version 4.4.0 or higher
- Tyk API Gateway: Version 5.0.0 or higher
- Dependencies:
  - [apictl](https://apim.docs.wso2.com/en/latest/reference/apictl/wso2-api-controller/)
  - [curl](https://curl.se/download.html)
  - [jq](https://jqlang.github.io/jq/)

## Disclaimer

This script is provided as-is, without warranty of any kind. It is intended as an example to assist in migrating API definitions from WSO2 to Tyk.
- Before running the script, ensure you have proper backups of your data.
- Test the script in a non-production environment first.
- Adjustments may be required to meet specific use cases or configurations.

Tyk assumes no liability for any issues arising from the use of this script. Use it at your own risk.

## Usage

To use the script, provide the connection details for both the WSO2 environment (source) and the Tyk environment (destination). These details are passed as parameters to the script:

```shell
./migrate_apis.sh <wso2_host> <wso2_username> <wso2_password> <tyk_host> <tyk_token>
```

### Script Parameters

1. `wso2_host`: WSO2 API Manager hostname
2. `wso2_username`: WSO2 login username
3. `wso2_password`: WSO2 login password
4. `tyk_host`: Tyk Dashboard URL
5. `tyk_token`: Tyk Dashboard API authorization token

### Example

Here’s an example command to use the script. It sets the WSO2 host to `https://localhost:9443` and uses `admin`/`admin` as the credentials. It also sets the Tyk Dashboard URL to `http://localhost:3000` with an API token of `e6110fdeabe94da657f816e2243985a7`:

```shell
./migrate-api-wso2-tyk.sh \
  https://localhost:9443 \
  admin \
  admin \
  http://localhost:3000 \
  e6110fdeabe94da657f816e2243985a7
```

## Notes

- The script creates or uses a WSO2 apictl environment called wso2-to-tyk-migration.
- Before running, it clears the WSO2 apictl export directory at `~/.wso2apictl/exported/migration/wso2-to-tyk-migration/tenant-default/apis`.
- If migrating APIs that use self-signed certificates, ensure the Tyk Gateway is configured to [skip verification for upstream services](https://tyk.io/docs/tyk-oss-gateway/configuration/#proxy_ssl_insecure_skip_verify).
- The script uses the -k flag with both `apictl` and `curl` to bypass SSL verification, as it is designed for Proof of Concept (PoC) environments that use self-signed certificates.

## Limitations

The script currently migrates the following API attributes:
- Name
- Listen path
- Upstream target
- Endpoint paths

Other API information, such as policies, security configurations, and documentation, must be migrated manually.

## Troubleshooting

If you encounter issues, consider the following:

- **Connectivity**: Ensure both WSO2 and Tyk instances are reachable from the machine running the script.
- **Authentication**: Verify that the `wso2_username`, `wso2_password`, and `tyk_token` credentials are correct.
- **Self-Signed Certificates**: For APIs migrated with self-signed certificates, verify that Tyk is configured to either trust the certificate or skip SSL verification.
