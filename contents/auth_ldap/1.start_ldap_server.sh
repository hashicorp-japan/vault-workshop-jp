# Get the relative directory name
# Sorry windows folks, you're gonna have to figure this out and modify it for you pleasure
IMAGE=osixia/openldap:1.2.2
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
. $DIR/env.sh

echo
echo "Running: $0: Starting LDAP Server"
docker pull ${IMAGE}
docker rm openldap &> /dev/null

echo docker run --hostname ${LDAP_HOSTNAME} \
  -p 389:389 \
  -p 689:689 \
  -e LDAP_ORGANISATION="${LDAP_ORGANISATION}" \
  -e LDAP_DOMAIN="${LDAP_DOMAIN}" \
  -e LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD}" \
  -e LDAP_READONLY_USER=${LDAP_READONLY_USER} \
  -e LDAP_READONLY_USER_USERNAME=${LDAP_READONLY_USER_USERNAME} \
  -e LDAP_READONLY_USER_PASSWORD=${LDAP_READONLY_USER_PASSWORD} \
  -v ${DIR}/ldif:/container/service/slapd/assets/config/bootstrap/ldif/custom \
  --name openldap \
  --detach ${IMAGE} --copy-service

docker run --hostname ${LDAP_HOSTNAME} \
  -p 389:389 \
  -p 689:689 \
  -e LDAP_ORGANISATION="${LDAP_ORGANISATION}" \
  -e LDAP_DOMAIN="${LDAP_DOMAIN}" \
  -e LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD}" \
  -e LDAP_READONLY_USER=${LDAP_READONLY_USER} \
  -e LDAP_READONLY_USER_USERNAME=${LDAP_READONLY_USER_USERNAME} \
  -e LDAP_READONLY_USER_PASSWORD=${LDAP_READONLY_USER_PASSWORD} \
  -v ${DIR}/ldif:/container/service/slapd/assets/config/bootstrap/ldif/custom \
  --name openldap \
  --detach ${IMAGE} --copy-service

