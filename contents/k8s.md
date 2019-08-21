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
kubectl port-forward vault-0 8200:8200
```

```shell
export VAULT_ADDR="http://127.0.0.1:8200"
vault operator init -recovery-shares=1 -recovery-threshold=1
vault operator unseal <UNSEAL_KEY>
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
vault read -format json database/creds/postgres-role
```

<details><summary>出力結果の例</summary>

```
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
</details>

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

`ClusterRole`の`system:auth-delegator`はK8sがデフォルトで持っているロールです。 このロールを`postgres-vault`のサービスアカウントにマッピングしてReviewToken APIを使った認証認可の権限を与えます。

```shell
kubectl apply -f postgres-serviceaccount.yml
```

## Vault Kubernetes Auth Methodの設定

次に(ここから本題です)VaultのK8s Auth Methodの設定を行います。これはKubernetesのサービスアカウントトークンを利用してVault認証するための設定です。これによってK8s上のPodからサービスアカウントを使ってVaultからPostgresのシークレットを取得することが可能になります。

VaultのK8s認証メソッドを有効化しておきます。

```shell
vault auth enable kubernetes
```

次にKubernetesの認証の設定を行います。以下の情報が必要です。

* `kubernetes_ca_cert`
  * TLSクライアントがK8s APIを使うための証明書
* `token_reviewer_jwt`
  * TokenReview APIにアクセスするために使用されるサービスアカウントトークン

これらを取得するために以下のコマンドを実行してください。
```
export VAULT_SA_NAME=$(kubectl get sa postgres-vault -o jsonpath="{.secrets[*]['name']}")
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)
export K8S_HOST=$(kubectl exec -it $VAULT_POD -- sh -c 'echo $KUBERNETES_SERVICE_HOST')
```

<details><summary>`kubectl get sa postgres-vault -o json`の例</summary>

```json
{
    "apiVersion": "v1",
    "kind": "ServiceAccount",
    "metadata": {
        "annotations": {
            "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"v1\",\"kind\":\"ServiceAccount\",\"metadata\":{\"annotations\":{},\"name\":\"postgres-vault\",\"namespace\":\"default\"}}\n"
        },
        "creationTimestamp": "2019-08-12T07:04:38Z",
        "name": "postgres-vault",
        "namespace": "default",
        "resourceVersion": "26321",
        "selfLink": "/api/v1/namespaces/default/serviceaccounts/postgres-vault",
        "uid": "7309c23d-bccf-11e9-9fcc-0800275363d6"
    },
    "secrets": [
        {
            "name": "postgres-vault-token-ts9x4"
        }
    ]
}
```
</details>

<details><summary>`kubectl get secret $VAULT_SA_NAME -o json`の例</summary>

```json
{
    "apiVersion": "v1",
    "data": {
        "ca.crt": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM1ekNDQWMrZ0F3SUJBZ0lCQVRBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwdGFXNXAKYTNWaVpVTkJNQjRYRFRFNU1EZ3hNREE0TVRVeE9Wb1hEVEk1TURnd09EQTRNVFV4T1Zvd0ZURVRNQkVHQTFVRQpBeE1LYldsdWFXdDFZbVZEUVRDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBS1FSCnNxRUV4SjZYU1QxZWNzeU9QVWlrQ1F4Rnd0bGcvbTc4RjVpUXI2clRndEpDRlZqTnhQZXdRaEtvcWlCLzg2WXYKT1UybFFyVEpycTFHazFpdFlDdXRlcjZtY0xLYk9wSHZYb01MUUtkZXlXRzdtcUEwb0pFY2xvWFZSNjI5V0pSSwplZ1FZb3B2Wk5IVVdYTnQxNEFjTjFDS1F0WmVhd3JqTHc0SXk2R3BvWHFLa0o3Q052QU45NEpQT0J3T25GbjUrCnMyNFhnd29yWnI4YWVOcUZNdGVWWkllMk9qS2c5dnJmb1Zvc3NNeTB1NmdwR3N4Q2tMUFFUeGthQnNwMW1KRWEKZHFFR082R2x2QTdYR1NocGR3RHk4UFM5b2ltVzVEQkhrUWFOWDYxQ1JzYlpLaVVhZXFtOCtJNllvYWxGNEdIegptV0hJRnhEcyttem43V2VUbHBVQ0F3RUFBYU5DTUVBd0RnWURWUjBQQVFIL0JBUURBZ0trTUIwR0ExVWRKUVFXCk1CUUdDQ3NHQVFVRkJ3TUNCZ2dyQmdFRkJRY0RBVEFQQmdOVkhSTUJBZjhFQlRBREFRSC9NQTBHQ1NxR1NJYjMKRFFFQkN3VUFBNElCQVFBZnA0VkQ4Sk1PTjdtYmxJaExmRmJTNmdFUUVuMit6eHU0dC9UZTIwVmhLenVHTlBsTwpyM09YV2trWWZBdVFHM3R1NGVDZ2pWR3NWeElPZndxVUswVEhRZ0tnNHFxRXdSdmEwNEhTK0ZKZk1yM1ZCZVFCCjhNbjNGSnErVS8wa3hrNmdWKy96WDVQa1BqalhJaHNmVlVGRzNsVjUydnIyeVIwQ0xIRnRkRkI2TzY3L2h0MVMKWFZsRExWQk1vVDVWbENlTDNjS2srZU4yUGZ2ZVlWRmxBbjlNemRqL2dLYjBVUFF1OFVLNDhyS0U5Ri96Tk5HZgp3T0FoVDI0VVVNUklxTVlNWXdsSEpOaVZqWEtBa05Eb3FFSVdYVHUwUW5uMFc1blUwR0RpNXEycVA5UDA1NWJWCnZkUG8zU3l3Ulk3YzU3UkJveHBpWVVxd1pjT2JZdk5WNC95UAotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==",
        "namespace": "ZGVmYXVsdA==",
        "token": "ZXlKaGJHY2lPaUpTVXpJMU5pSXNJbXRwWkNJNklpSjkuZXlKcGMzTWlPaUpyZFdKbGNtNWxkR1Z6TDNObGNuWnBZMlZoWTJOdmRXNTBJaXdpYTNWaVpYSnVaWFJsY3k1cGJ5OXpaWEoyYVdObFlXTmpiM1Z1ZEM5dVlXMWxjM0JoWTJVaU9pSmtaV1poZFd4MElpd2lhM1ZpWlhKdVpYUmxjeTVwYnk5elpYSjJhV05sWVdOamIzVnVkQzl6WldOeVpYUXVibUZ0WlNJNkluQnZjM1JuY21WekxYWmhkV3gwTFhSdmEyVnVMWFJ6T1hnMElpd2lhM1ZpWlhKdVpYUmxjeTVwYnk5elpYSjJhV05sWVdOamIzVnVkQzl6WlhKMmFXTmxMV0ZqWTI5MWJuUXVibUZ0WlNJNkluQnZjM1JuY21WekxYWmhkV3gwSWl3aWEzVmlaWEp1WlhSbGN5NXBieTl6WlhKMmFXTmxZV05qYjNWdWRDOXpaWEoyYVdObExXRmpZMjkxYm5RdWRXbGtJam9pTnpNd09XTXlNMlF0WW1OalppMHhNV1U1TFRsbVkyTXRNRGd3TURJM05UTTJNMlEySWl3aWMzVmlJam9pYzNsemRHVnRPbk5sY25acFkyVmhZMk52ZFc1ME9tUmxabUYxYkhRNmNHOXpkR2R5WlhNdGRtRjFiSFFpZlEuWGF0TktwVmpFNnJLZ3JzN2t3TTE3ODU1UXhBLVc2b0lRTWlUZW9rQmJEZjRfd3EwcWJzN2pwSEJnRlRVMkdORl9DTWkwSmlHa0loUFJ1X3NIUTkzaHVwdDBJWFFFZzNURFR2OXFsVFdlN1hQUFRaLXhqdUpRUFhxNENHMzd1R2x1T1J4UmdWWktVM3FaSnV4WlZINmNSdjJMeF9aZDN5MFppN09EUkZWaEJtLUtpeFN1czdFeHdjd3BUQlRoQ3EtSm12c25od3ZmOFlHeDdEdUUtQ3FndEdjMXJnZ2N1djd1WC1BbnZKRXRiLTVwdEgwZWlVX3F4dXNHb2c5LW5iMXRnYTR3dHJfd1V4bWZCMFAxZWp0S2hUSm1ZZ3dIdi1zYlNYTGVLZ3VLNVRLYXBMSV9EaWFXdnRDb3RVS0VmM3JibXdBM28xSlBZMGlMbFdGTVJrNmdB"
    },
    "kind": "Secret",
    "metadata": {
        "annotations": {
            "kubernetes.io/service-account.name": "postgres-vault",
            "kubernetes.io/service-account.uid": "7309c23d-bccf-11e9-9fcc-0800275363d6"
        },
        "creationTimestamp": "2019-08-12T07:04:38Z",
        "name": "postgres-vault-token-ts9x4",
        "namespace": "default",
        "resourceVersion": "26320",
        "selfLink": "/api/v1/namespaces/default/secrets/postgres-vault-token-ts9x4",
        "uid": "730db7e6-bccf-11e9-9fcc-0800275363d6"
    },
    "type": "kubernetes.io/service-account-token"
}
```
</details>

取得した値を使って認証の設定を行います。これはVaultがKubernetesに接続するための設定です。`kubernetes_host`で設定したエンドポイントに対して取得した`token_reviewer_jwt`で認証します。

```
vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="https://$K8S_HOST:443" \
  kubernetes_ca_cert="$SA_CA_CRT"
```

サービスアカウントロールにアタッチされるロールを作ります。`default`ネームスペースの先ほど作った`postgres-vault`サービスアカウントを認可して、Vault上で作った`postgres-policy`の権限を付与しています。

```
vault write auth/kubernetes/role/postgres \
    bound_service_account_names=postgres-vault \
    bound_service_account_namespaces=default \
    policies=postgres-policy \
    ttl=24h
```

つまりここで`postgres-vault`で認証されたクライアントに対して下記のように作った権限を与えるという意味です。

```hcl
path "database/creds/postgres-role" {
  capabilities = ["read"]
}
path "sys/leases/renew" {
  capabilities = ["create"]
}
path "sys/leases/revoke" {
  capabilities = ["update"]
}
```

## TemporarilyのPodで試す

アプリで利用する前にTemporarilyのPodを立てて一連の流れをテストしてみましょう。`postgres-vault`のサービスアカウントを設定したPodを一つ起動してみます。

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

次にこれを利用してKubernetes Auth Methodを使ってVaultにログインします。ログインには`auth/kubernetes/login`のエンドポイントを使います。

```
VAULT_K8S_LOGIN=$(curl --request POST --data '{"jwt": "'"$KUBE_TOKEN"'", "role": "postgres"}' http://vault.default.svc.cluster.local:8200/v1/auth/kubernetes/login)
```

ログイン情報を確認しておきましょう。トークンが発行され、認証されたクライアントに`postgres-policy`が割り当てられていることがわかります。

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
</details>

`.auth.client_token`がVaultのトークンなのでこれを取得します。

```
X_VAULT_TOKEN=$(echo $VAULT_K8S_LOGIN | jq -r '.auth.client_token')
```

次に、このトークンを使ってVaultのAPIをコールしてPostgresのシークレットを生成しましょう。`database/creds/ROLE_NAME`がエンドポイントです。

```
POSTGRES_CREDS=$(curl --header "X-Vault-Token: $X_VAULT_TOKEN" http://vault.default.svc.cluster.local:8200/v1/database/creds/postgres-role)
```

確認します。

```
$ echo $POSTGRES_CREDS | jq

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

<kbd>
  <img src="https://miro.medium.com/max/700/1*qfojP76kbu-L7rYDMTx8JQ.png">
</kbd>

PodからVaultのシークレットを使ってシークレットを発行する一連の手順を確認しました。

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
</details>

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
* [Helm Chart for Vault](https://github.com/hashicorp/vault-helm)
* [Helm Chart for Postgres](https://github.com/helm/charts/tree/master/stable/postgresql)
* [Sample App Blog](https://medium.com/@gmaliar/dynamic-secrets-on-kubernetes-pods-using-vault-35d9094d169)
