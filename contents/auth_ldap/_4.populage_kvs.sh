#!/bin/bash

vault write secret/ldap/it password="foo"
vault write secret/ldap/security password="bar" 
vault write secret/ldap/engineering password="hoge" 
