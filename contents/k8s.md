# Kubernetes連携を試す

VaultとKubernetesは様々な形で連携できます。例えば、

* VaultをK8sのPodとして稼働させる
* K8s上のPodからVaultの動的シークレットを取得する

などです。

ここでは以下のような構成で試してみます。

![](https://github-image-tkaburagi.s3-ap-northeast-1.amazonaws.com/vault-workshop/Screen+Shot+2019-08-19+at+15.01.12.png)

* Rails <-> PostgresでRailsからデータを取得
* Vault <-> PostgresでPostgresのシークレットを発行、更新
* Rails <-> VaultでPostgresのシークレットを取得
* Vault <-> K8sでサービスアカウントの連携

## install Vault on K8s

まずはVaultをKuberenetes上にデプロイしてみます。[前日アナウンスされた](https://www.hashicorp.com/blog/announcing-the-vault-helm-chart)Helmでのインストールです。今回は練習のためK8s上にデプロイしますが、2019年8月19日現在Enterprise版ではサポート対象外の構成となります。近い将来サポート対象になるはずです。

インストールは簡単です。minikubeが起動していることを確認してください。

```shell
$ git clone https://github.com/hashicorp/vault-helm.git
$ helm install ./vault-helm --name=vault
```

インストールが完了したら別の端末を立ち上げてポートフォワードします。

```shell
port-forward vault-0 8200:8200
```

```shell
export VAULT_ADDR="http://127.0.0.1:8200"
vault operator init -recovery-shares=1 -recovery-threshold=1
vault unseal <UNSEAL_KEY>
```

```console
$ vault status
Key                      Value
---                      -----
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.1.3
Cluster Name             vault-cluster-26e7cd60
Cluster ID               6c2c7a37-c0c5-c9dd-e118-9b38fa8fb920
HA Enabled               false
```

`Sealed`が`false`になっていればOKです。データベースシークレットエンジンを有効化しておきましょう。

```shell
vault secrets enable database
```

次にPostgresをK8s上にインストールします。

## install Postgres on K8s

次にPostgresをインストールします。

```
helm install --name postgres \
             --set image.repository=postgres
             --set image.tag=10.6 \
             --set postgresqlDataDir=/data/pgdata \
             --set persistence.mountPath=/data/ \
             stable/postgresql
```

Podの起動を確認しましょう。

```console
$ kubectl get pods
NAME                                           READY   STATUS    RESTARTS   AGE
postgres-postgresql-0                          1/1     Running   1          7d8h
vault-0                                        0/1     Running   1          7d12h
```

Postgresユーザのパスワードを設定します。

```shell
kubectl exec -it postgres-postgresql-0 -- psql -U postgres
```

```shell
ALTER USER postgres WITH PASSWORD 'postgres';
quit
```

# Vault - Postgres間の連携設定

前に実施したMySQLと同様、Postgresのシークレットを払い出すための設定をK8s上のVaultに行っていきます。まずはConfigの設定です。

```
vault write database/config/postgres \
plugin_name=postgresql-database-plugin \
allowed_roles="postgres-role" \
connection_url="postgresql://postgres:postgres@postgres-postgresql.default.svc.cluster.local:5432/postgres?sslmode=disable"
```

次に`postgres-role`の設定です。

```
vault write database/roles/postgres-role \
db_name=postgres \
creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA PUBLIC TO \"{{name}}\";" \
default_ttl="1h" \
max_ttl="24h"
```

このロールを使ってシークレットを払い出します。

```console
$ vault read -format json database/creds/postgres-role
{
  "request_id": "98843e81-cb6d-10cc-a7a8-96754fcebbe1",
  "lease_id": "database/creds/postgres-role/RMTEnlBPjOQt4JKql7Qsm4Z3",
  "lease_duration": 3600,
  "renewable": true,
  "data": {
    "password": "A1a-3ViKAGli3CCm4VUm",
    "username": "v-root-postgres-bSpP7p8SwwCNENAFyTfK-1566227063"
  },
  "warnings": null
}
```

最後にポリシーの設定を行います。このポリシーはK8s上のPodのアプリから取得するトークンに紐づくポリシーです。つまり、アプリケーションに与える権限となります。

```shell
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

```shell
$ vault policy write postgres-policy postgres-policy.hcl
```

## Kubernetes側の設定

次はK8sの設定です。`Service Account`と[TokenReview API](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.10/#tokenreview-v1-authentication-k8s-io)を使ってサービスアカウントに認証するための`Cluster Role Binding`を作ります。

```shell
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

Applyします。

```shell
kubectl apply -f postgres-serviceaccount.yml
```

## Vault Kubernetes Auth Methodの設定

次に(ここから本題です)VaultのK8s Auth Methodの設定を行います。これはKubernetesのサービスアカウントを利用してVault認証するための設定です。これによってK8s上のPodからサービスアカウントを使ってVaultからPostgresのシークレットを取得することが可能になります。

VaultのK8s認証メソッドを有効化しておきます。

```shell
vault auth enable kubernetes
```

次にKubernetesの認証の設定を行います。以下の情報が必要です。

* `kubernetes_ca_cert`
  * TLSクライアントがK8s APIを使うための証明書
* `token_reviewer_jwt`
  * TokenReview APIにアクセスするために使用されるサービスアカウントJWT

これらを取得するために以下のコマンドを実行してください。出力内容を確認しながら実行したい場合は`kubectl`は個別で実行してみてください。

```
export VAULT_SA_NAME=$(kubectl get sa postgres-vault -o jsonpath="{.secrets[*]['name']}")
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)
export K8S_HOST=$(kubectl exec -it $VAULT_POD -- sh -c 'echo $KUBERNETES_SERVICE_HOST')
```

取得した値を使って認証の設定を行います。Kubernetes authメソッドは、サービスアカウントJWTを検証し、Kubernetes TokenReview APIでそれらの存在を検証します。このエンドポイントは、JWT署名とKubernetes APIにアクセスするために必要な情報を検証するために使用される公開キーを構成します。

```
vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="https://$K8S_HOST:443" \
  kubernetes_ca_cert="$SA_CA_CRT"
```

サービスアカウントロールにアタッチされるロールを作ります。

```
vault write auth/kubernetes/role/postgres \
    bound_service_account_names=postgres-vault \
    bound_service_account_namespaces=default \
    policies=postgres-policy \
    ttl=24h
```

## TemporarilyのPodで試す

アプリで利用する前にTemporarilyのPodを立てて一連の流れをテストしてみましょう。`postgres-vault`のサービスアカウントを使ってPodを一つ起動してみます。

```
$ kubectl run tmp --rm -i --tty --serviceaccount=postgres-vault --image alpine
```

ログインできたら

* サービスアカウントトークンをfetchして
* Vaultにログインし、
* Vaultが発行したトークンを使って、
* Postgresのシークレットを利用して

みます。

Aplineに必要なパッケージをインストールして、サービスアカウントトークンを取得してfetchします

```
apk update
apk add curl postgresql-client jq
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
```

次にこれを利用してKubernetes Auth Methodを使ってVaultにログインします。

```
VAULT_K8S_LOGIN=$(curl --request POST --data '{"jwt": "'"$KUBE_TOKEN"'", "role": "postgres"}' http://vault.default.svc.cluster.local:8200/v1/auth/kubernetes/login)
```

ログイン情報を確認しておきましょう。

```
echo $VAULT_K8S_LOGIN | jq
```

<details><summary>出力結果</summary>

```
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

`.auth.client_token`がVaultのAPI実行のためには必要なのでこれを取得します。

```
X_VAULT_TOKEN=$(echo $VAULT_K8S_LOGIN | jq -r '.auth.client_token')
```

次に、VaultのAPIをコールしてPostgresのシークレットを生成しましょう。

```
POSTGRES_CREDS=$(curl --header "X-Vault-Token: $X_VAULT_TOKEN" http://vault.default.svc.cluster.local:8200/v1/database/creds/postgres-role)
```

確認します。

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

このユーザを使ってPostgresを利用しています。

```
PGUSER=$(echo $POSTGRES_CREDS | jq -r '.data.username')
export PGPASSWORD=$(echo $POSTGRES_CREDS | jq -r '.data.password')
psql -h postgres-postgresql -U $PGUSER postgres -c 'SELECT * FROM pg_catalog.pg_tables;'
```

テーブルが表示され正しくシークレットが発行できることが確認できるはずです。

## 実際のWebアプリのPodから利用してみる

次はいよいよRailsのアプリからVaultを経由してPostgresを扱ってみます。

以下のYamlを任意のディレクトリに作成してください。

<details><summary>vault-rails.yml</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-dynamic-secrets-rails
  labels:
    app: vault-dynamic-secrets-rails
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vault-dynamic-secrets-rails
  template:
    metadata:
      labels:
        app: vault-dynamic-secrets-rails
    spec:
      serviceAccountName: postgres-vault
      initContainers:
        - name: vault-init
          image: everpeace/curl-jq
          command:
            - "sh"
            - "-c"
            - >
              KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token);
              curl --request POST --data '{"jwt": "'"$KUBE_TOKEN"'", "role": "postgres"}' http://vault.default.svc.cluster.local:8200/v1/auth/kubernetes/login | jq -j '.auth.client_token' > /etc/vault/token;
              X_VAULT_TOKEN=$(cat /etc/vault/token);
              curl --header "X-Vault-Token: $X_VAULT_TOKEN" http://vault.default.svc.cluster.local:8200/v1/database/creds/postgres-role > /etc/app/creds.json;
          volumeMounts:
            - name: app-creds
              mountPath: /etc/app
            - name: vault-token
              mountPath: /etc/vault
      containers:
        - name: rails
          image: gmaliar/vault-dynamic-secrets-rails:0.0.1
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          resources:
            limits:
              memory: "150Mi"
              cpu: "200m"
          volumeMounts:
            - name: app-creds
              mountPath: /etc/app
            - name: vault-token
              mountPath: /etc/vault
        - name: vault-manager
          image: everpeace/curl-jq
          command:
            - "sh"
            - "-c"
            - >
              X_VAULT_TOKEN=$(cat /etc/vault/token);
              VAULT_LEASE_ID=$(cat /etc/app/creds.json | jq -j '.lease_id');
              while true; do
                curl --request PUT --header "X-Vault-Token: $X_VAULT_TOKEN" --data '{"lease_id": "'"$VAULT_LEASE_ID"'", "increment": 3600}' http://vault.default.svc.cluster.local:8200/v1/sys/leases/renew;
                sleep 3600;
              done
          lifecycle:
            preStop:
              exec:
                command:
                  - "sh"
                  - "-c"
                  - >
                    X_VAULT_TOKEN=$(cat /etc/vault/token);
                    VAULT_LEASE_ID=$(cat /etc/app/creds.json | jq -j '.lease_id');
                    curl --request PUT --header "X-Vault-Token: $X_VAULT_TOKEN" --data '{"lease_id": "'"$VAULT_LEASE_ID"'"}' http://vault.default.svc.cluster.local:8200/v1/sys/leases/revoke;
          volumeMounts:
            - name: app-creds
              mountPath: /etc/app
            - name: vault-token
              mountPath: /etc/vault
      volumes:
        - name: app-creds
          emptyDir: {}
        - name: vault-token
          emptyDir: {}
```

Applyします。

```shell
kubectl apply -f vault-rails.yml
```

Pod名を取得しましょう。

```shell
kubectl get po -l app=vault-dymanic-secrets-rails -o wide
```

Pod名を引数にPort fowardの設定を行います。

```shell
port-forward <POD_NAME_1> 3001:3000
port-forward <POD_NAME_2> 3002:3000
```

ブラウザでアクセスするとPostgresのユーザ名とパスワードがPodごとに発行されていることがわかるでしょう。

<kbd>
  <img src="https://miro.medium.com/max/700/1*1wq5AFgky7JDDsKM0EOdmg.png">
</kbd>

<kbd>
  <img src="https://miro.medium.com/max/700/1*kERi7ESQ6oWUeIEs-5f11A.png">
</kbd>

## 参考リンク
* [Kubernetes with Vault](https://www.vaultproject.io/docs/platform/k8s/index.html)
* [Kubernetes Auth Method](https://www.vaultproject.io/docs/auth/kubernetes.html)
* [Kubernetes Auth Method API](https://www.vaultproject.io/api/auth/kubernetes/index.html)
* [Sample App Blog](https://medium.com/@gmaliar/dynamic-secrets-on-kubernetes-pods-using-vault-35d9094d169)