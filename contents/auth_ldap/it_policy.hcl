# Policy for IT peopld

path "secret/ldap" {
	capabilities = [ "list" ]
}

path "secret/ldap/it" {
	capabilities = [ "create", "read", "update", "delete", "list" ]
}
