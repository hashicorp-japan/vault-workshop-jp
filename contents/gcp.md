# GCP のシークレットエンジンを試す

GCP シークレットエンジンではロールセットの定義に基づいた GCP のキーを動的に発行することが可能です。GCP のキー発行のワークフローをシンプルにし、TTL などを設定することでよりセキュアに利用できます。

サポートしているクレデンシャルタイプは下記の三つです。

* Service Account Key
* Token

このハンズオンでは GCP アカウントが必要です。[こちら](https://cloud.google.com/free/)からアカウントを作成していください。

## セットアップ

GCP シークレットエンジンを扱うためのセットアップを行います。

まずは Service Account の作成です。この Service Account は Vault に登録するためのもので、この Servie Account のキーを利用して実際にプロジェクト等で利用するキーを発行します。

GCP のコンソールにログインして、`Navigation Menu`から`IAM&Admin` -> `Service accounts`と進んでください。

`CREATE SERVICE ACCOUNT`をクリックして、任意の名前を入力したら`CREATE`してください。`Select a role`で`Project` -> `Owner`を選んでください。

`CONTIUNE`で進んだら、`CREATE KEY`で JSON のキーを発行します。**このキーはプロジェクトの Owner の権限を持つので絶対に外部に漏らさないように保管してください。**

次に API を有効化します。Vault は上記で発行したキーを使って GCP のシークレットを払い出すわけですがそのためには`IAM`と`Cloud Resource Manager`の API を有効にする必要があります。

[https://console.developers.google.com/apis/dashboard](https://console.developers.google.com/apis/dashboard)にアクセスして`+ ENABLE APIS AND SERVICES`をクリックします。

次の画面で検索ボックスから`IAM`, `Cloud Resource Mananger`と`Compute`を探してそれぞれ`Enable`ボタンで有効化します。

次に Vault のセットアップです。以下のコマンドで GCP シークレットエンジンを有効化しましょう。

```shell
$ export VAULT_ADDR="http://127.0.0.1:8200"
$ vault secrets enable gcp
```

最後に`gcloud`コマンドをインストールします。[こちら](https://cloud.google.com/sdk/)からインストールしてください。

これでセットアップは完了です。この後ロールセットに基づいた GCP のキーを動的に生成していきます。

## Vault の設定

次に Vault 側の設定です。Vault 側には

* GCP API を実行してキーを発行するための Vault 側へのキーの登録
* Vault が発行するキーに付与する権限

の設定が必要です。

まずは先ほど発行した Service Account のキーを Vault のコンフィグとして登録します。`KEY_JSON.json`は自身のファイル名に置き換えてください。


```shell
$ vault write gcp/config credentials=@KEY_JSON.json
```

Vault は内部的にこの鍵を使って GCP の API を実行して動的に新しいキーを発行して行きます。その際、発行するキーにどのような権限を与えるかを指定する必要があります。その設定を`gcp/roleset`で定義します。

`project`は`Project ID`を入力します。

> Project ID が分からない方は
> `gloud auth login`コマンドを実行してログインしてください。
> ログインが成功するとターミナル上に ID が表示されます。


`secret_type`には`service_account_key`もしくは`token`のいずれかを入力します。

ここでは Service Account を使ってみましょう。`bindings`は権限の設定です。まずは自身のプロジェクトに対して`viewer`の権限を設定してみましょう。

```shell
$ cat << EOF > mybindings.hcl
resource "//cloudresourcemanager.googleapis.com/projects/<PROJECT_ID>" {
  roles = ["roles/viewer"]
}
EOF
```

これを`gcp/roleset/ROLE_NAME`の`bindings`で指定します。ここでは`pj-viewer`という名前でロールセットを作成します。

```shell
$ vault write gcp/roleset/pj-viewer \
    project="peak-elevator-237302" \
    secret_type="service_account_key"  \
    bindings=@mybindings.hcl
```

作成したロールセットの一覧は以下のように確認します。

```console
$ vault list gcp/rolesets
Keys
----
pj-viewer
```

内容を確認したい時は read します。

```console
$ vault read gcp/roleset/pj-viewer
Key                      Value
---                      -----
bindings                 map[//cloudresourcemanager.googleapis.com/projects/peak-elevator-237302:[roles/viewer]]
project                  peak-elevator-237302
secret_type              service_account_key
service_account_email    vaultpj-viewer-1575172760@peak-elevator-237302.iam.gserviceaccount.com
```

これ以降`pj-viewer`を指定してキーを作成すると`bindings`に定義された権限のキーが発行されます。

これで Vault 側の設定は完了です。

## キーを発行する

それでは実際にキーを発行してみましょう。

```console
$ vault read -format=json gcp/key/pj-viewer | jq -r '.data.private_key_data' > gcp.key.encoded
```

`gcp.key.encoded`にエンコードされたキーが出力されているでしょう。

```console
$ base64 -D gcp.key.encoded > gcp.key
```

gcp.key の中身を確認してください。これでキーが作成されました。

このキーを使ってログインしてみましょう。

```shell
$ gcloud auth activate-service-account  --key-file=gcp.key
```

ログインしたら権限を試してみましょう。

```shell
$ gcloud iam service-accounts list

$ gcloud compute disk-types list

$ gcloud compute disk-types describe local-ssd
```

これらは`viewer`の権限で実行することが出来るでしょう。一方以下のコマンドはエラーが発生するはずです。

```console
$ gcloud iam service-accounts create auser-vault-handson
ERROR: (gcloud.iam.service-accounts.create) User [vaultpj-viewer-1575172760@peak-elevator-237302.iam.gserviceaccount.com] does not have permission to access project [peak-elevator-237302] (or it may not exist): Permission iam.serviceAccounts.create is required to perform this operation on project projects/peak-elevator-237302.
```

## 動的なシークレットを試す

ここまででキーを発行してきましたが、Vault の特徴の一つは動的なシークレット管理です。Vault から発行するシークレットは全て TTL を付与します。

デフォルトだと 768h の有効期限ですが、最低限の期間に設定し、それ以降は無効にすることがベストです。まずは準備をします。

```console
$ gcloud iam service-accounts list
NAME                                                                EMAIL                                                                        DISABLED
admin                                                               
Service account for Vault secrets backend role set pj-viewer        vaultpj-viewer-1575172760@peak-elevator-237302.iam.gserviceaccount.com       False
```

`vaultpj-viewer-***@***iam.gserviceaccount.com`をコピーして別のターミナルを立ち上げ、以下のコマンドでキーのリストを監視します。

```console
$ watch -n 1 iam service-accounts keys list --iam-account=vaultpj-viewer-***@***iam.gserviceaccount.com
KEY_ID                                    CREATED_AT            EXPIRES_AT
10c1eec7578c74dc06d1312613fe02bc4dc0ebe3  2019-12-01T03:59:28Z  9999-12-31T23:59:59Z
```

### 手動でのシークレット破棄を試す

次は Revoke(破棄)を試してみます。Revoke にはマニュアルと自動の 2 通りの方法があります。

まずは手動を試してみます。先ほどと同様にシークレットを発行します。`lease_id`はあとで使うのでメモしておいてください。これを使ってシークレットの`renew`, `revoke`などのライフサイクルを管理します。

```console
$ vault read gcp/key/pj-viewer
Key                 Value
---                 -----
lease_id            gcp/key/pj-viewer/1UC2B3DckozLyNHX5K4Ks4h9
lease_duration      768h
lease_renewable     true
key_algorithm       KEY_ALG_RSA_2048
key_type            TYPE_GOOGLE_CREDENTIALS_FILE
private_key_data
```

`watch`の内容を見るとキーが発行されているでしょう。

```
KEY_ID                                    CREATED_AT            EXPIRES_AT
10c1eec7578c74dc06d1312613fe02bc4dc0ebe3  2019-12-01T03:59:28Z  9999-12-31T23:59:59Z
a07f4979f3e8a40350418325002b1956cc46cf48  2019-12-01T04:02:58Z  2029-11-28T04:02:58Z
```

これを削除してみます。先ほどメモした Lease ID を引数に、`revoke`コマンドを実行するだけです。

```shell
$ vault lease revoke <LEASE_ID>
```

`watch`の内容を見るとキーが破棄されていることがわかります。

```
KEY_ID                                    CREATED_AT            EXPIRES_AT
10c1eec7578c74dc06d1312613fe02bc4dc0ebe3  2019-12-01T03:59:28Z  9999-12-31T23:59:59Z
```

次に TTL に基づいた自動での破棄を試してみます。

### 自動でのシークレット破棄を試す

`watch`の出力はそのままにしておいてください。TTL の設定をしてみましょう。

```console
$ vault write gcp/config ttl=2m max_ttl=10m
$ vault read gcp/config

Key        Value
---        -----
max_ttl    10m
ttl        2m
```

TTL を 2 分に設定しました。`max_ttl`は`renew`というオペレーションで延長できる最大の有効期限です。

```console
$ vault read gcp/key/pj-viewer
Key                 Value
---                 -----
lease_id            gcp/key/pj-viewer/XWUOnUut8QYauHiBRSXHXs9o
lease_duration      2m
lease_renewable     true
key_algorithm       KEY_ALG_RSA_2048
key_type            TYPE_GOOGLE_CREDENTIALS_FILE
private_key_data
```

`watch`の端末を見るとキーが一つ発行されていることがわかるでしょう。

```console
KEY_ID                                    CREATED_AT            EXPIRES_AT
10c1eec7578c74dc06d1312613fe02bc4dc0ebe3  2019-12-01T03:59:28Z  9999-12-31T23:59:59Z
3aeebad8ea118e648b909a1ebefb80205e9df29e  2019-12-01T04:00:52Z  9999-12-31T23:59:59Z
```

このキーは 2 分後に Vault から自動で削除されます。2 分後ターミナルを確認してください。

```console
KEY_ID                                    CREATED_AT            EXPIRES_AT
10c1eec7578c74dc06d1312613fe02bc4dc0ebe3  2019-12-01T05:28:30Z  2029-11-28T05:28:30Z
```

ユーザが削除されていることがわかるでしょう。

## 参考リンク
* [GCP Secret Engine](https://www.vaultproject.io/docs/secrets/gcp/index.html)
* [Role Set Bindings](https://www.vaultproject.io/docs/secrets/gcp/index.html#roleset-bindings)
* [GCP Secret Engine API](https://www.vaultproject.io/api/secret/gcp/index.html)