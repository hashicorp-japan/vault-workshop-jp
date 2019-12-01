# VaultをPKIエンジンとして扱う

Vaultで扱うことの出来る「シークレット」は多岐に渡ります。今まで扱ってきたCloudのユーザアカウントやデータベースのパスワード、静的なユーザ名とシークレットなどの他にサーバ証明書もVaultで扱うことが出来ます。

これを使うことで従来多くの時間を割いていた証明書の発行を短いサイクルで行うことが可能です。Vaultには`PKI Secret Engine`というシークレットエンジンが用意されており、これを利用することでVaultが認証局として機能して動的に証明書を発行します。

`Root CA`, `Intermediate CA`の両方を扱うことが出来、外部の`Root CA`と連携をし`Intermediate CA`であるVaultをインターフェースに発行することも出来ますし、Vaultを`Root CA`と`Intermediate CA`両方の役割をさせて`self-singed`な証明書を発行することも出来ます。

ここでは両方の役割をVaultに持たせるパターンを試してみます。

## PKIとして設定する

まずはPKI Secret Engineを有効化します。ここではVaultをRoot、Intermediateの両方として扱うため、別のパスでそれぞれEnableしていきます。

```shell
$ vault secrets enable -path="pki_root" pki
$ vault secrets enable -path="pki_intermediate" pki
```

これ以降`pki_root`をルートCA、`pki_intermediate`を中間CAとして扱います。ドメインは仮で`vault-handson.lab`とします。

`/pki/root/generate/:type`のエンドポイントで自己署名のルートCA証明書とプライベートキーを発行します。

```shell
$ export DOMAIN=vault-handson.lab

$ vault write pki_root/root/generate/internal common_name="${DOMAIN} Root CA" ttl=24h > ca_root.crt.pem
```

以下のコマンドでRoot CAが作成されたことが確認できます。

```console
$ curl -s --header "X-Vault-Token: <VAULT_TOKEN>" http://127.0.0.1:8200/v1/pki_root/ca/pem
-----BEGIN CERTIFICATE-----
MIIDrDCCApSgAwIBAgIUQneY8K+YH9M5DOuFVDVxHwM2CG8wDQYJKoZIhvcNAQEL
BQAwJDEiMCAGA1UEAxMZdmF1bHQtaGFuZHNvbi5sYWIgUm9vdCBDQTAeFw0xOTEy
~~~~~
-----END CERTIFICATE-----
```

次に証明書wp発行するエンドポイントと証明書失効リストを配信するためのエンドポイントを設定します。

```shell
$ vault write pki_root/config/urls \
issuing_certificates="http://127.0.0.1:8200/v1/pki_root/ca" \
crl_distribution_points="http://127.0.0.1:8200/v1/pki_root/crl"
```

次にIntermediate側の設定です。まずはCSR(証明書署名リクエスト)の作成です。`intermediate/generate/:type`のエンドポイントです。

```shell
$ vault write -format=json pki_intermediate/intermediate/generate/internal \
common_name="${DOMAIN} Intermediate Authority" ttl="12h" \
| jq -r '.data.csr' > pki_intermediate.csr
```

`pki_intermediate.csr`ファイルを見るとCSRが生成されていることがわかるでしょう。次にこのCSRに対して、先ほど作ったRoot CAを使ってサインをしていきます。

```shell
$ vault write -format=json pki_root/root/sign-intermediate \
csr=@pki_intermediate.csr \
format=pem_bundle ttl="12h" \
| jq -r '.data.certificate' > ca_intermediate.cert.pem
```

Root CAによってCSRがサインされ、中間CAとしての証明書が発行されました。証明書を検証してみましょう。

``` shell
$ openssl x509 -in ca_intermediate.cert.pem -text -noout
```

`CA Issuers - URI:http://127.0.0.1:8200/v1/pki_root/ca`となっており、VaultのRoot CAで発行されたことがわかります。


この証明書を中間CAにインポートします。

```shell
$ vault write pki_intermediate/intermediate/set-signed \
certificate=@ca_intermediate.cert.pem
```

以下のコマンドで確認してみましょう。

```console
$ curl -s --header "X-Vault-Token: <VAULT_TOKEN>" http://127.0.0.1:8200/v1/pki_intermediate/ca/pem

-----BEGIN CERTIFICATE-----
MIIDxDCCAqygAwIBAgIUY/zc2qyWWEaXZdEhSezI2qTJWoswDQYJKoZIhvcNAQEL
BQAwJDEiMCAGA1UEAxMZdmF1bHQtaGFuZHNvbi5sYWIgUm9vdCBDQTAeFw0xOTEy
~~~~
-----END CERTIFICATE-----
```

## 証明書を発行する

これでRoot CAとIntermediate CAの準備が出来ました。最後に証明書を発行していきます。発行する前にロールを定義する必要があります。

ロールとは、発行する証明書に与える権限の論理名のようなイメージです。

* 発行を許可するドメイン
* サブドメインの利用可否
* ワイルドカードドメインの利用可否

などを設定します。下記は`vault-handson.lab`が利用でき、サブドメインを許可する例です。

```shell
$ vault write pki_intermediate/roles/vault-dot-lab \
allowed_domains="vault-handson.lab" allow_subdomains=true max_ttl="12h"
```

最後にこのロールを使って証明書を発行しましょう。

```shell
$ vault write pki_intermediate/issue/vault-dot-lab \
common_name="contents.vault-handson.lab" ttl="24h"
```

`vault-handson.lab`のドメインの`contents`というサブドメインで発行をしています。出力される各シークレットを例えば以下のように

* ca_chain => ca-chain.crt.pem
* private_key => private.key.pem
* certificate => server.crt.pem

保存し、これをサーバ、コンテナやロードバランサにセットすることで証明書として扱うことが出来ます。

例えばAWSにインポートするときは以下のように実行します。

```
aws acm import-certificate \
--certificate file://./server.crt.pem \
--private-key file://./private.key.pem \
--certificate-chain file://./ca-chain.crt.pem
```

最後にcertificateの出力結果を`server.crt.pem`として保存をして証明書を検証してみます。

```shell
openssl x509 -in server.cert.pem  -text -noout
```

正しく発行されているでしょう。VaultではこのようにRoot CA、Intermediate CAとしてVaultを扱う、もしくは既存のRoot CAとVault上のIntermediate CAを連携させて、TTL付きの証明書を権限に応じて動的に、迅速に発行することが可能です。

## 参考リンク
* [PKI Secret Engine](https://www.vaultproject.io/docs/secrets/pki/index.html)
* [PKI Secret Engine API](https://www.vaultproject.io/api/secret/pki/index.html)
* [PKI Roles](https://www.vaultproject.io/api/secret/pki/index.html#create-update-role)