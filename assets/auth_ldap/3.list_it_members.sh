#!/bin/bash

#if [ $# -eq 0 ]
#	then
#		echo 'Needs to supply argument'
#		echo '  $1 = <arg>'
#		exit 1
#fi

ldapsearch -x -H ldap://127.0.0.1 -b cn=it,ou=um_group,dc=ourcorp,dc=com -D cn=read-only,dc=ourcorp,dc=com -w devsecopsFTW 
