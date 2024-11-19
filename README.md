# WSO2 to Tyk API Migration Script

## Overview

This bash script automates the migration of APIs from WSO2 API Manager to Tyk API Gateway, simplifying the process of transferring API configurations between platforms.

## Prerequisites

The script uses the following tools. Make sure they are available before running the script.

- `apictl` (WSO2 API Controller)
- `curl`
- `jq`

In addition, the script must be able to access the referenced WSO2 and Tyk environments.

## Usage

```shell
./migrate_apis.sh <wso2_host> <wso2_username> <wso2_password> <tyk_host> <tyk_token>
```

Script parameters:
1. `wso2_host`: WSO2 API Manager hostname
2. `wso2_username`: WSO2 login username
3. `wso2_password`: WSO2 login password
4. `tyk_host`: Tyk Dashboard URL
5. `tyk_token`: Tyk Dashboard authorization token

The example below sets the WSO2 publisher host as `https://localhost:9443`, and uses `admin`/`admin` as the username/password. It also sets the Tyk dashboard host as `http://localhost:3000` and the authorization token as `e6110fdeabe94da657f816e2243985a7`:

```shell
./migrate-api-wso2-tyk.sh \
  https://localhost:9443 \
  admin \
  admin \
  http://localhost:3000 \
  e6110fdeabe94da657f816e2243985a7
```

### Notes

The script:
- Creates/uses a WSO2 `apictl` environment called `wso2-to-tyk-migration`
- Clears the WSO2 `apictl` export directory `~/.wso2apictl/exported/migration/wso2-to-tyk-migration/tenant-default/apis` prior to running the migration

### Limitations

The script currently migrates the following API information:
- Name
- Listen path
- Upstream target
- Endpoint paths

Other information must be migrated manually.
