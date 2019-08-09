#!/bin/bash

#if [ $# -eq 0 ]
#	then
#		echo 'Needs to supply argument'
#		echo '  $1 = <arg>'
#		exit 1
#fi

# create policies
vault policy write it_policy it_policy.hcl
vault policy write security_policy security_policy.hcl

# set up uniqueMember group logins
vault write auth/ldap-um/groups/it policies=it_policy
vault write auth/ldap-um/groups/security policies=security_policy

