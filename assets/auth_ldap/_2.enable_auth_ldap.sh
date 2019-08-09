#!/bin/bash

. env.sh

echo "Running: $0: Enable and Configure the LDAP Auth Method"
vault auth enable -path=ldap-um ldap

echo "Configure Unique Member group lookups"

# Using group of unique names lookups

vault write auth/ldap-um/config \
    url="${LDAP_URL}" \
    binddn="${BIND_DN}" \
    bindpass="${BIND_PW}" \
    userdn="${USER_DN}" \
    userattr="${USER_ATTR}" \
    groupdn="${GROUP_DN}" \
    groupfilter="${UM_GROUP_FILTER}" \
    groupattr="${UM_GROUP_ATTR}" \
    insecure_tls=true

