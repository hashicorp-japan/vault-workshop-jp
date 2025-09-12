# GCP Auth Method を利用してクライアントを認証する

Table of Contents                                                                                                          
=================                                                                                                                                                                                
  * [Vault 事前準備](#vault-事前準備)                                                
  * [GCP 事前準備](#gcp事前準備)
  * [GCP Auth Method の設定 (IAM 編)](#gcp-auth-methodの設定-iam編)
  * [GCP Auth Method の設定 (GCE 編)](#gcp-auth-methodの設定-gce編)
  * [参考リンク](#参考リンク)

GCP Auth Method では GCP の`IAM Service Account`, `Google Compute Engine Instances`を利用してクライアントを認証することができます。

* `Service Account`は IAM Service Account を利用しての認証
* `Google Compute Engine Instances`は GCE インスタンスのメタデータを利用して認証

このハンズオンでは GCP アカウントが必要です。[こちら](https://cloud.google.com/free/)からアカウントを作成していください。

## Vault 事前準備

まずは Vault 上のデータとポリシーを準備します。Root Token でログインし、以下のコマンドを実行してください。

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

このポリシーは後ほどクライアントが利用する GCP Service Account との紐付けを行い、GCP Auth でログインしたユーザに与える Vault の権限になります。

ここでは`KV Secret Engine`の`kv/cred-1`の read のみ出来る権限として設定しています。

## GCP 事前準備

GCP 側の設定です。

まず、トップ画面の検索ボックスから`IAM Service Account Credentials API`と検索し`Enable`をクリックして API を有効化します。

次に GCP を使って認証をするために Vault 側に設定する Service Account の発行です。Vault はこのシークレットを利用して GCP へ認証を依頼します。

GCP のコンソールにログインして、`Navigation Menu`から`IAM&Admin` -> `Service accounts`と進んでください。

`CREATE SERVICE ACCOUNT`をクリックして、名前に`vault-server`と入力してロールの選択に移ります。

* `Compute Viewer`
* `Service Account Key Admin`

の二つを選択し、`CREATE`してください。

`CONTIUNE`で進んだら、`CREATE KEY`で JSON のキーを発行します。ダウンロードされたキーは`.gcp-vault-auth-config-key.json`にリネームします。

```sh
$ mv /path/to/***********.json ~/.gcp-vault-auth-config-key.json
```

次に Vault にログインするクライアント側の Service Account を発行します。

GCP のコンソールにログインして、`Navigation Menu`から`IAM&Admin` -> `Service accounts`と進んでください。

`CREATE SERVICE ACCOUNT`をクリックして、名前に`vault-client`と入力してロールの選択に移ります。

* `Service Account Token Creator`

を選択し、`CREATE`してください。

`CONTIUNE`で進んだら、`CREATE KEY`で JSON のキーを発行します。ダウンロードされたキーは`.gcp-vault-client-key.json`にリネームします。

```sh
$ mv /path/to/***********.json ~/.gcp-vault-client-key.json
```

これで GCP 側の準備は完了です。

## GCP Auth Method の設定 (IAM 編)

[こちら](https://www.vaultproject.io/docs/auth/gcp#iam-login)がワークフローです。

最後に`GCP Auth Method`の設定を行います。

GCP 認証を有効化し、Vault 用の Service Account をセットします。Vault はこの Service Account を利用して GCP へ認証を依頼します。

```sh
$ vault auth enable gcp
$ vault write auth/gcp/config credentials=@.gcp-vault-auth-config-key.json
```

`role`を作成します。`read-cred-1`のポリシーを先ほど発行した Service Account にバインドします。これでこの Service Account を使ってログインしたユーザに`read-cred-1`で設定した Vault の権限を与えることができます。

`GCP_PRJ`にご自身の GCP プロジェクト名をセットしてください。

```sh
$ GCP_PRJ=se-kabu
$ vault write auth/gcp/role/read-cred \
    type="iam" \
    policies="read-cred-1" \
    bound_service_accounts="vault-client@${GCP_PRJ}.iam.gserviceaccount.com"
```

これで設定は完了です。ログインしてみましょう。ログインには

* CLI Helper を使って認証に必要な JWT を取得して Vault にリクエストする(IAM のみ有効)
* CLI 使って別で生成した JWT を使ってリクエストする
* API を実行する

の 3 パターンがあります。今回は CLI Helper を使ってみます。

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

ロールとポリシーで設定したように今回作成した Service Account では`kv/cred-1`を read するためのポリシーがバインドされているため設定通りに動作していることがわかります。

## GCP Auth Method の設定 (GCE 編)

次に GCE のメタデータを利用して認証するパターンを試してみます。

手順の前に以下の GCE インスタンスを立ち上げてください。

* Service Account: `vault-client`
* Zone: `asia-northeast1-b`
* Label: `foo:bar`
* SSH ログインが有効
* curl コマンドが利用可能
* インターネットアクセス可能

GCE インスタンスが立ち上がったら、Vault 側の設定を加えます。まずは Root Token でログインし直してください。

```sh
$ vault login
```

次に GCE 認証用のロールを定義します。

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

先ほどは Service Account で認証しましたが、今回は GCE のメタデータを利用します。その他にも以下のメタデータをセットできます。

* GCE インスタンスに付与される`Service Account`
* `Instance Group`
* `Region`

各パラメタータをリスト型で設定できるため複数の値を入れることもできます。

これで Vault 側の設定は完了です。

次に GCE インスタンスに SSH で入り、次のコマンドを実行してください。

```sh
$ ROLE=read-cred-gce

$ curl \
  --header "Metadata-Flavor: Google" \
  --get \
  --data-urlencode "audience=http://vault/${ROLE}" \
  --data-urlencode "format=full" \
  "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity"
```

インスタンスのメタデータサーバから JWT の発行を依頼しています。これは GCE インスタンス上からのみ有効なリクエストです。

発行された JWT をコピーしてローカルの端末に戻ります。先ほど発行された JWT を使ってログインしてみましょう。(**今回は Vault がローカルマシンで起動している前提のためローカルから実行しますが、通常は GCE からリーチできる所に配置し GCE インスタンスから利用します。**)

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
$ vault token lookup ${VTOKEN}
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

このように GCE インスタンスが`GCE Metadata Server`と連携をし Signed JWT を取得し、それを利用して Vault の認証することができます。

これを利用することで GCE インスタンスのメタ情報をもとに GCE インスタンスに Vault のアクセス権限を付与することが可能です。

## 参考リンク
* [GCP Auth Method](https://www.vaultproject.io/docs/auth/gcp)
* [GCP Auth Mehotd API](https://www.vaultproject.io/api/auth/gcp)
* [Generating JWTs](https://www.vaultproject.io/docs/auth/gcp#generating-jwts)
* [Demonstrating the GCE Auth method for Vault](https://petersouter.xyz/demonstrating-the-gce-auth-method-for-vault/)
