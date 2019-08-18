## install Vault on K8s
```
helm install ./vault-helm-0.1.1 --name=vault
```

## install postgres on K8s
```
helm install --name postgres \
             --set image.repository=postgres
             --set image.tag=10.6 \
             --set postgresqlDataDir=/data/pgdata \
             --set persistence.mountPath=/data/ \
             stable/postgresql
```
```
kubectl exec -it postgres-postgresql-0 -- psql -U postgres
```
```
ALTER USER postgres WITH PASSWORD 'postgres';
```
```
kubectl port-forward vault-0 8200
```
```
vault write database/config/postgres \
plugin_name=postgresql-database-plugin \
allowed_roles="postgres-role" \
connection_url="postgresql://postgres:postgres@postgres-postgresql.default.svc.cluster.local:5432/postgres?sslmode=disable"
```
```
vault write database/roles/postgres-role \
db_name=postgres \
creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA PUBLIC TO \"{{name}}\";" \
default_ttl="1h" \
max_ttl="24h"
```
```
vault read -format json database/creds/postgres-role
```
```
vault write database/config/postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="postgres-role" \
    connection_url="postgresql://root:root@triangular-goose-postgresql.default.svc.cluster.local:5432/rails_development?sslmode=disable"
```
```
$ cat > postgres-policy.hcl <<EOF
path "database/creds/postgres-role" {
  capabilities = ["read"]
}
path "sys/leases/renew" {
  capabilities = ["create"]
}
path "sys/leases/revoke" {
  capabilities = ["update"]
}
EOF
```
```
$ vault policy write postgres-policy postgres-policy.hcl
```
```
cat > postgres-serviceaccount.yml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: postgres-vault
  namespace: default
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-vault
EOF
```
```
kubectl apply -f postgres-serviceaccount.yml
```
```
export VAULT_SA_NAME=$(kubectl get sa postgres-vault -o jsonpath="{.secrets[*]['name']}")
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)
export K8S_HOST=$(kubectl exec -it $VAULT_POD -- sh -c 'echo $KUBERNETES_SERVICE_HOST'                                      kabu@/Users/kabu/kubernetes
10.96.0.1)
```
```
vault auth enable kubernetes
```
```
vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="https://$K8S_HOST:443" \
  kubernetes_ca_cert="$SA_CA_CRT"
```
```
vault write auth/kubernetes/role/postgres \
    bound_service_account_names=postgres-vault \
    bound_service_account_namespaces=default \
    policies=postgres-policy \
    ttl=24h
```


```
VAULT_K8S_LOGIN=$(curl --request POST --data '{"jwt": "'"$KUBE_TOKEN"'", "role": "postgres"}' http://vault.default.svc.cluster.local:8200/v1/auth/kubernetes/login)
```
```
echo $VAULT_K8S_LOGIN | jq

{
  "request_id": "071f4939-26d5-ef37-0311-30dc64b804d7",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": null,
  "wrap_info": null,
  "warnings": null,
  "auth": {
    "client_token": "s.z79s26iFrza2LxvQBy6Xyscs",
    "accessor": "6T7Xt14PsltZZh1TLVffOePb",
    "policies": [
      "default",
      "postgres-policy"
    ],
    "token_policies": [
      "default",
      "postgres-policy"
    ],
    "metadata": {
      "role": "postgres",
      "service_account_name": "postgres-vault",
      "service_account_namespace": "default",
      "service_account_secret_name": "postgres-vault-token-ts9x4",
      "service_account_uid": "7309c23d-bccf-11e9-9fcc-0800275363d6"
    },
    "lease_duration": 86400,
    "renewable": true,
    "entity_id": "a2b587be-d518-c4f5-fff5-1ba0fecedbbe",
    "token_type": "service",
    "orphan": true
  }
}
```

```
X_VAULT_TOKEN=$(echo $VAULT_K8S_LOGIN | jq -r '.auth.client_token')
```

```
POSTGRES_CREDS=$(curl --header "X-Vault-Token: $X_VAULT_TOKEN" http://vault.default.svc.cluster.local:8200/v1/database/creds/postgres-role)
```

```
echo $POSTGRES_CREDS | jq

{
  "request_id": "d31b68f9-54f1-0ec2-8cc9-bbd31fc7d3f5",
  "lease_id": "database/creds/postgres-role/I0ImdJrSVDoQ7UlMLfWuHDaN",
  "renewable": true,
  "lease_duration": 3600,
  "data": {
    "password": "A1a-WfWDZtqLzuid4Ili",
    "username": "v-kubernet-postgres-qkxMrIGHABBwr40HJStX-1565595560"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```
```
PGUSER=$(echo $POSTGRES_CREDS | jq -r '.data.username')
export PGPASSWORD=$(echo $POSTGRES_CREDS | jq -r '.data.password')
```
```
psql -h postgres-postgresql -U $PGUSER postgres -c 'SELECT * FROM pg_catalog.pg_tables;'
```

