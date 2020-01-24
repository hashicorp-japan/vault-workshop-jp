# Azureのシークレットエンジンを試す

Azureシークレットエンジンではロールの定義に基づいたAzureのService Principalを動的に発行することが可能です。Azureのキー発行のワークフローをシンプルにし、TTLなどを設定することでよりセキュアに利用できます。

## Azureのセットアップ

[こちら](https://github.com/hashicorp-japan/vault-workshop/blob/master/assets/azure-guide.md)を参考にAzureのセットアップを行なって下さい。

## IAMユーザの動的発行

まずシークレットエンジンをenableにします。

```shell
$ export VAULT_ADDR="http://127.0.0.1:8200"
$ vault secrets enable azure
```

次にVaultがAzureのAPIを実行するために必要なキーを登録します。

```shell
export SUB_ID="***********"
export TENANT_ID="***********"
export CLIENT_ID="***********"
export CLIENT_SECRET="***********"

$ vault write azure/config \
        subscription_id="${SUB_ID}" \
        client_id="${CLIENT_ID}" \
        client_secret="${CLIENT_SECRET}" \
        tenant_id="${TENANT_ID}"
```

`subscription_id`, `client_id`, `client_secret`, `tenant_id`はご自身の環境に合わせたものに書き換えてください。ここでは必ずしもAzureのAdminユーザを登録する必要はなく、ロールやユーザを発行できるユーザであれば大丈夫です。

次にロールを登録します。このロールがVaultから払い出されるユーザの権限と紐付きます。ロールは複数登録することが可能です。今回はまずは全てのリソースに対するRead Onlyのロールを作成しています。

```shell
$ vault write azure/roles/reader azure_roles=-<<EOF
    [
      {
        "role_name": "Reader",
        "scope": "/subscriptions/${SUB_ID}/resourceGroups/vault-resource-group"
      }
    ]
EOF
```

別端末を開いて`watch`コマンドでユーザのリストを監視します。

```console
$ export TENANT_ID="***********"
$ watch -n az ad sp list --query "[].{id:appId, tenant:appOwnerTenantId}" | grep -B 1 ${TENANT_ID}

    "id": "4c4411ee-9654-4acf-b242-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "80343551-a8cf-494a-9b40-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
```

>az cliにログイン出来ていない場合、以下のコマンドでログインしてください。
>
>```shell
>$  az login --service-principal \
>    -u "${CLIENT_ID}" \
>    -p "${CLIENT_SECRET}" \
>    --tenant "${TENANT_ID}"
>```

>Windowsなどで実行できない場合は手動で実行して下さい。

元の端末に戻り、ロールを使ってAzureのシークレットを発行してみましょう。

```console
$ vault read azure/creds/reader

Key                Value
---                -----
lease_id           azure/creds/reader/OXL8Ua8oGnvQukcEU8taA3Ni
lease_duration     768h
lease_renewable    true
client_id          *******************
client_secret      *******************
```

この`watch`の出力結果を見るとユーザが増えていることがわかります。`lease_id`はあとで使うのでメモしておいてください。
`client_id`と`client_secret`もメモしておいて下さい。

```
    "id": "4c4411ee-9654-4acf-b242-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "80343551-a8cf-494a-9b40-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "70788f51-a1ff-472e-8b74-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
```

このユーザを使って動作を確認してみましょう。

`-u`: 先ほど生成した`client_id` 
`-p`: 先ほど生成した`client_secret`

をそれぞれ入力します。

```shell
$  az login --service-principal \
 -u "*****" \
 -p "*****" \
 --tenant ${TENANT_ID}
```

新しい端末を立ち上げて以下のコマンドを実行します。

```console
$ az network vnet list

$ az storage account list

$ az vm list

$ az storage account create -n $(openssl rand -hex 10) -g vault-resource-group
The client '****************' with object id '****************' does not have authorization to perform action 'Microsoft.Storage/storageAccounts/write' over scope '/subscriptions/****************/resourceGroups/vault-resource-group/providers/Microsoft.Storage/storageAccounts/ea00f5eb2a503375d265' or the scope is invalid. If access was recently granted, please refresh your credentials.
```

Roleに設定した通りReadのオペレーションを行うことができますが、Createなどその他の操作を行うことが出来ないことがわかるでしょう。

## Revokeを試す

az cliのユーザを元のユーザに切り替えておきます。`watch`を実行している端末を一度`ctrl+c`で抜けて以下のコマンドでユーザでログインをし直します。

```shell
$  az login --service-principal \
    -u "${CLIENT_ID}" \
    -p "${CLIENT_SECRET}" \
    --tenant "${TENANT_ID}"
```
```console
$ watch -n az ad sp list --query "[].{id:appId, tenant:appOwnerTenantId}" | grep -B 1 ${TENANT_ID}

    "id": "4c4411ee-9654-4acf-b242-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "80343551-a8cf-494a-9b40-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "70788f51-a1ff-472e-8b74-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
```

シンプルな手順でユーザが発行できることがわかりましたが、次はRevoke(破棄)を試してみます。Revokeにはマニュアルと自動の2通りの方法があります。

まずはマニュアルでの実行手順です。`vault read azure/creds/reader`を実行した際に発行された`lease_id`をコピーしてください。

```shell
$ vault lease revoke azure/creds/reader/<LEASE_ID>
```

`watch`の実行結果を見ると一つユーザが削除されているでしょう。

```
    "id": "4c4411ee-9654-4acf-b242-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "80343551-a8cf-494a-9b40-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
```

次に自動Revokeです。デフォルトではTTLが`765h`になっています。これは数分にしてみましょう。

```shell
vault write azure/roles/reader ttl=2m max_ttl=10m azure_roles=-<<EOF
    [
      {
        "role_name": "Reader",
        "scope": "/subscriptions/${SUB_ID}/resourceGroups/vault-resource-group"
      }
    ]
EOF
```

```console
$ vault read azure/roles/reader
Key                      Value
---                      -----
application_object_id    n/a
azure_groups             <nil>
azure_roles              [map[role_id:/subscriptions/6343b729-dfc6-4798-898b-b8eb9c9f4afb/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7 role_name:Reader scope:/subscriptions/6343b729-dfc6-4798-898b-b8eb9c9f4afb/resourceGroups/vault-resource-group]]
max_ttl                  10m
ttl                      2m
```

それではこの状態でユーザを発行します。

```console
$ vault read azure/creds/reader
Key                Value
---                -----
lease_id           azure/creds/reader/ct6a4XdSvmiV1d9zcfAVy2cS
lease_duration     2m
lease_renewable    true
client_id          ****************
client_secret      ****************
```

`watch`の実行結果を見るとユーザが増えています。今度は2分後にこのユーザは自動で削除されます。

```
    "id": "4c4411ee-9654-4acf-b242-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "80343551-a8cf-494a-9b40-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "70788f51-a1ff-472e-8b74-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
```

2分後、再度見てみるとユーザが削除されていることがわかるでしょう。

```json
    "id": "4c4411ee-9654-4acf-b242-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
    "id": "80343551-a8cf-494a-9b40-*******************",
    "tenant": "a67e8730-8fe4-453a-a239-e62d4df0a815"
--
```

自動Revokeには今回のように`ttl`で時間として指定したり`user_limit`というパラメータで回数で指定し、その回数使用されたら自動で破棄することなども可能です。

ここまで試したようにVaultでは以下のようなことが可能となり、安全にAzureのシークレットを扱うことが出来ます。

1. 発行するシークレットをVault経由で動的に発行が可能
2. 発行する際に必要な権限のみを付与してクライアントに提供することが可能
3. TTLやuser_limitを設定し動的にシークレットをRevokeすることが可能

このような機能で設定ファイルに静的に記述したり、長い間同じキーを複数クライアントで使い続けるなどの危険な運用を回避することが出来ます。

## 参考リンク
* [Azure Secret Engine](https://www.vaultproject.io/docs/secrets/azure/index.html)
* [Azure Secret Engine API](https://www.vaultproject.io/api/secret/azure/index.html)
