# Policy for security people

path "secret/ldap" {
	capabilities = [ "list" ]
}

path "secret/ldap/security" {
	capabilities = [ "create", "read", "update", "delete", "list" ]
}
