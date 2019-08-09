#!/bin/bash

#if [ $# -eq 0 ]
#	then
#		echo 'Needs to supply argument'
#		echo '  $1 = <arg>'
#		exit 1
#fi

vault login -method=ldap -path=ldap-um username=eve password=thispasswordsucks 
