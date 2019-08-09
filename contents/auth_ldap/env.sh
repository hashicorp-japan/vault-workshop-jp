# env.sh -- Environment variables to assist with this demo

export KV_PATH=kv-blog
export KV_VERSION=2

export IP_ADDRESS=127.0.0.1

# LDAP Server settings
export LDAP_HOST=${LDAP_HOST:-${IP_ADDRESS}}
export LDAP_URL="ldap://${LDAP_HOST}"
export LDAP_ORGANISATION=${LDAP_ORGANISATION:-"OurCorp Inc"}
export LDAP_DOMAIN=${LDAP_DOMAIN:-"ourcorp.com"}
export LDAP_HOSTNAME=${LDAP_HOSTNAME:-"ldap.ourcorp.com"}
export LDAP_READONLY_USER=${LDAP_READONLY_USER:-true}
export LDAP_READONLY_USER_USERNAME=${LDAP_READONLY_USER_USERNAME:-read-only}
export LDAP_READONLY_USER_PASSWORD=${LDAP_READONLY_USER_PASSWORD:-"devsecopsFTW"}
export LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASSWORD:-"hashifolk"}


# LDAP Connect settings
export BIND_DN=${BIND_DN:-"cn=read-only,dc=ourcorp,dc=com"}
export BIND_PW=${BIND_PW:-"devsecopsFTW"}
export USER_DN=${USER_DN:-"ou=people,dc=ourcorp,dc=com"}
export USER_ATTR=${USER_ATTR:-"cn"}
export GROUP_DN=${GROUP_DN:-"ou=um_group,dc=ourcorp,dc=com"}
export UM_GROUP_FILTER=${UM_GROUP_FILTER:-"(&(objectClass=groupOfUniqueNames)(uniqueMember={{.UserDN}}))"}
export UM_GROUP_ATTR=${UM_GROUP_ATTR:-"cn"}
export MO_GROUP_FILTER=${MO_GROUP_FILTER:-"(&(objectClass=person)(uid={{.Username}}))"}
export MO_GROUP_ATTR=${MO_GROUP_ATTR:-"memberOf"}
# This is the default user password created by the default ldif creator if none other is specified
export USER_PASSWORD=${USER_PASSWORD:-"thispasswordsucks"}

