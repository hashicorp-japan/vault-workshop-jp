# GCP Auth Methodを利用してクライアントを認証する

Table of Contents                                                                                                          
=================                                                                                                                                                                                
  * [Vault 事前準備](#vault-事前準備)                                                
  * [GCP事前準備](#gcp事前準備)
  * [GCP Auth Methodの設定 (IAM編)](#gcp-auth-methodの設定-iam編)
  * [GCP Auth Methodの設定 (GCE編)](#gcp-auth-methodの設定-gce編)
  * [参考リンク](#参考リンク)

GCP Auth MethodではGCPの`IAM Service Account`, `Google Compute Engine Instances`を利用してクライアントを認証することができます。

* `Service Account`はIAM Service Accountを利用しての認証
* `Google Compute Engine Instances`はGCEインスタンスのメタデータを利用して認証

このハンズオンではGCPアカウントが必要です。[こちら](https://cloud.google.com/free/)からアカウントを作成していください。

## Vault 事前準備

まずはVault上のデータとポリシーを準備します。Root Tokenでログインし、以下のコマンドを実行してください。

```sh
$ vault kv put kv/cred-1 name=user-1 password=passwd
$ vault kv put kv/cred-2 name=user-2 password=dwssap
```

次にポリシーを作成します。

```sh
$ vault policy write read-cred-1 -<<EOF
path "kv/cred-1" {
  capabilities = [ "read" ]
}
EOF
```

このポリシーは後ほどクライアントが利用するGCP Service Accountとの紐付けを行い、GCP Authでログインしたユーザに与えるVaultの権限になります。

ここでは`KV Secret Engine`の`kv/cred-1`のreadのみ出来る権限として設定しています。

## GCP事前準備

GCP側の設定です。

まず、トップ画面の検索ボックスから`IAM Service Account Credentials API`と検索し`Enable`をクリックしてAPIを有効化します。

次にGCPを使って認証をするためにVault側に設定するService Accountの発行です。Vaultはこのシークレットを利用してGCPへ認証を依頼します。

GCPのコンソールにログインして、`Navigation Menu`から`IAM&Admin` -> `Service accounts`と進んでください。

`CREATE SERVICE ACCOUNT`をクリックして、名前に`vault-server`と入力してロールの選択に移ります。

* Compute Viewer
* Service Account Key Admin

の二つを選択し、`CREATE`してください。

`CONTIUNE`で進んだら、`CREATE KEY`でJSONのキーを発行します。ダウンロードされたキーは`.gcp-vault-auth-config-key.json`にリネームします。

```sh
$ mv /path/to/***********.json ~/.gcp-vault-auth-config-key.json
```

次にVaultにログインするクライアント側のService Accountを発行します。

GCPのコンソールにログインして、`Navigation Menu`から`IAM&Admin` -> `Service accounts`と進んでください。

`CREATE SERVICE ACCOUNT`をクリックして、名前に`vault-server`と入力してロールの選択に移ります。

* Service Account Token Creator

の二つを選択し、`CREATE`してください。

`CONTIUNE`で進んだら、`CREATE KEY`でJSONのキーを発行します。ダウンロードされたキーは`.gcp-vault-client-key.json`にリネームします。

```sh
$ mv /path/to/***********.json ~/.gcp-vault-client-key.json
```

これでGCP側の準備は完了です。

## GCP Auth Methodの設定 (IAM編)

こちらがワークフローです。(refer: https://www.vaultproject.io/docs/auth/gcp#iam-login)

<kbd>
  <img src="https://d33wubrfki0l68.cloudfront.net/663efd308386c18b4de4792670e895c2c52ac23f/6b4b3/img/vault-gcp-iam-auth-workflow.svg">
</kbd> 

最後に`GCP Auth Method`の設定を行います。

GCP認証を有効化し、Vault用のService Accountをセットします。VaultはこのService Accountを利用してGCPへ認証を依頼します。


```sh
$ vault auth enable gcp
$ vault write auth/gcp/config credentials=@.gcp-vault-auth-config-key.json
```

`role`を作成します。`read-cred-1`のポリシーを先ほど発行したService Accountにバインドします。これでこのService Accountを使ってログインしたユーザに`read-cred-1`で設定したVaultの権限を与えることができます。

`GCP_PRJ`にご自身のGCPプロジェクト名をセットしてください。

```sh
$ GCP_PRJ=se-kabu
$ vault write auth/gcp/role/read-cred \
    type="iam" \
    policies="read-cred-1" \
    bound_service_accounts="vault-client@${GCP_PRJ}.iam.gserviceaccount.com"
```

これで設定は完了です。ログインしてみましょう。ログインには

* CLI Helperを使って認証に必要なJWTを取得してVaultにリクエストする(IAMのみ有効)
* CLI使って別で生成したJWTを使ってリクエストする
* APIを実行する

の3パターンがあります。今回はCLI Helperを使ってみます。

```sh
$ vault login -method=gcp \
    role="read-cred" \
    service_account="vault-client@${GCP_PRJ}.iam.gserviceaccount.com" \
    project="${GCP_PRJ}" \
    jwt_exp="15m" \
    credentials=@.gcp-vault-client.key.json
```

これでログインができました。以降のリクエストはここで発行されたトークンを使って実行されます。トークンの権限を試してみましょう。

```console
$ vault kv get kv/cred-1
====== Data ======
Key         Value
---         -----
name        user-1
password    passwd

$ vault kv get kv/cred-2
Error reading kv/cred-2: Error making API request.

URL: GET http://127.0.0.1:8200/v1/kv/cred-2
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

ロールとポリシーで設定したように今回作成したService Accountでは`kv/cred-1`をreadするためのポリシーがバインドされているため設定通りに動作していることがわかります。

## GCP Auth Methodの設定 (GCE編)

次にGCEのメタデータを利用して認証するパターンを試してみます。

手順の前に以下のGCEインスタンスを立ち上げてください。

* Service Account: `vault-client`
* Zone: `asia-northeast1-b`
* Label: `foo:bar`
* SSHログインが有効
* curlコマンドが利用可能
* インターネットアクセス可能

GCEインスタンスが立ち上がったら、Vault側の設定を加えます。まずはRoot Tokenでログインし直してください。

```sh
$ vault login
```

次にGCE認証用のロールを定義します。

```sh
$ ZONES=asia-northeast1-b
$ LABELS=foo:bar
$ vault write auth/gcp/role/read-cred-gce \
    type="gce" \
    policies="read-cred-1" \
    bound_projects=${GCP_PRJ} \
    bound_zones=${ZONES} \
    bound_labels=${LABELS}
```

先ほどはService Accountで認証しましたが、今回はGCEのメタデータを利用します。その他にも以下のメタデータをセットできます。

* GCEインスタンスに付与される`Service Account`
* `Instance Group`
* `Region`

各パラメターたをリスト型で設定できるため複数の値を入れることもできます。

これでVault側の設定は完了です。

次にGCEインスタンスにSSHで入り、次のコマンドを実行してください。

```sh
$ ROLE=read-cred-gce

$ curl \
  --header "Metadata-Flavor: Google" \
  --get \
  --data-urlencode "audience=http://vault/${ROLE}" \
  --data-urlencode "format=full" \
  "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity"
```

インスタン氏のメタデータサーバからJWTの発行を依頼しています。これはGCEインスタンス上からのみ有効なリクエストです。

発行されたJWTをコピーしてローカルの端末に戻ります。先ほど発行されたJWTを使ってログインしてみましょう。(**今回はVaultがローカルマシンで起動している前提のためローカルから実行しますが、通常はGCEからリーチできる所に配置し、CEインスタンスから利用します。**)

こちらのワークフローがわかりやすいです。(refer: https://petersouter.xyz/demonstrating-the-gce-auth-method-for-vault/)
<kbd>
  <img src="https://petersouter.xyz/images/2018/07/jwt_gcp_explanation.png">
</kbd> 

```sh
$ JWT=<COPIED_TOKEN>
$ VTOKEN=$(vault write -field=token auth/gcp/login \
        role="read-cred-gce" \
        jwt=${JWT})
$ echo ${VTOKEN}
```

トークンが発行されたはずです。

```console
$ vault token lookup
Key                 Value
---                 -----
accessor            29wEzEdQ3O3yxgDXqzAfKD8G
creation_time       1591159208
creation_ttl        768h
display_name        gcp-terraform
entity_id           796c99f7-718c-1023-69fb-1da9da0b0f01
expire_time         2020-07-05T13:40:08.801533+09:00
explicit_max_ttl    0s
id                  s.uwhaAkaS9A7C2FVAGOIe1SKA
issue_time          2020-06-03T13:40:08.801538+09:00
meta                map[instance_creation_timestamp:1591159129 instance_id:6418544221929256035 instance_name:terraform project_id:se-kabu project_number:707116064532 role:read-cred-gce service_account_email:vault-client@se-kabu.iam.gserviceaccount.com service_account_id:101585660406385936575 zone:asia-northeast1-b]
num_uses            0
orphan              true
path                auth/gcp/login
policies            [default read-cred-1]
renewable           true
ttl                 767h59m50s
type                service
```

`read-cred-1`のポリシーが付与されていることがわかるでしょう。

このトークンを使ってログインして先ほどと同様にテストしてみます。

```console
$ vault login ${VTOKEN}
$ vault kv get kv/cred-1
====== Data ======
Key         Value
---         -----
name        user-1
password    passwd

$ vault kv get kv/cred-2
Error reading kv/cred-2: Error making API request.

URL: GET http://127.0.0.1:8200/v1/kv/cred-2
Code: 403. Errors:

* 1 error occurred:
    * permission denied
```

設定した通りの権限となっているでしょう。

このようにGCEインスタンスが`GCE Metadata Server`と連携をしSigned JWTを取得し、それを利用してVaultの認証することができます。

これを利用することでGCEインスタンスのメタ情報をもとにGCEインスタンスにVaultのアクセス権限を付与することが可能です。

## 参考リンク
* [GCP Auth Method](https://www.vaultproject.io/docs/auth/gcp)
* [GCP Auth Mehotd API](https://www.vaultproject.io/api/auth/gcp)
* [Generating JWTs](https://www.vaultproject.io/docs/auth/gcp#generating-jwts)
* [Demonstrating the GCE Auth method for Vault](https://petersouter.xyz/demonstrating-the-gce-auth-method-for-vault/)
