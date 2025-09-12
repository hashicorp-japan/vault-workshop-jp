# Vault を PKI エンジンとして扱う

Vault で扱うことの出来る「シークレット」は多岐に渡ります。今まで扱ってきた Cloud のユーザアカウントやデータベースのパスワード、静的なユーザ名とシークレットなどの他にサーバ証明書も Vault で扱うことが出来ます。

これを使うことで従来多くの時間を割いていた証明書の発行を短いサイクルで行うことが可能です。Vault には`PKI Secret Engine`というシークレットエンジンが用意されており、これを利用することで Vault が認証局として機能して動的に証明書を発行します。

`Root CA`, `Intermediate CA`の両方を扱うことが出来、外部の`Root CA`と連携をし`Intermediate CA`である Vault をインターフェースに発行することも出来ますし、Vault を`Root CA`と`Intermediate CA`両方の役割をさせて`self-singed`な証明書を発行することも出来ます。

ここでは両方の役割を Vault に持たせるパターンを試してみます。

## PKI として設定する

まずは PKI Secret Engine を有効化します。ここでは Vault を Root、Intermediate の両方として扱うため、別のパスでそれぞれ Enable していきます。

```shell
$ vault secrets enable -path="pki_root" pki
$ vault secrets enable -path="pki_intermediate" pki
```

これ以降`pki_root`をルート CA、`pki_intermediate`を中間 CA として扱います。ドメインは仮で`vault-handson.lab`とします。

`/pki/root/generate/:type`のエンドポイントで自己署名のルート CA 証明書とプライベートキーを発行します。

```shell
$ export DOMAIN=vault-handson.lab

$ vault write pki_root/root/generate/internal common_name="${DOMAIN} Root CA" ttl=24h > ca_root.crt.pem
```

以下のコマンドで Root CA が作成されたことが確認できます。

```console
$ curl -s --header "X-Vault-Token: <VAULT_TOKEN>" http://127.0.0.1:8200/v1/pki_root/ca/pem
-----BEGIN CERTIFICATE-----
MIIDrDCCApSgAwIBAgIUQneY8K+YH9M5DOuFVDVxHwM2CG8wDQYJKoZIhvcNAQEL
BQAwJDEiMCAGA1UEAxMZdmF1bHQtaGFuZHNvbi5sYWIgUm9vdCBDQTAeFw0xOTEy
~~~~~
-----END CERTIFICATE-----
```

次に証明書 wp 発行するエンドポイントと証明書失効リストを配信するためのエンドポイントを設定します。

```shell
$ vault write pki_root/config/urls \
issuing_certificates="http://127.0.0.1:8200/v1/pki_root/ca" \
crl_distribution_points="http://127.0.0.1:8200/v1/pki_root/crl"
```

次に Intermediate 側の設定です。まずは CSR(証明書署名リクエスト)の作成です。`intermediate/generate/:type`のエンドポイントです。

```shell
$ vault write -format=json pki_intermediate/intermediate/generate/internal \
common_name="${DOMAIN} Intermediate Authority" ttl="12h" \
| jq -r '.data.csr' > pki_intermediate.csr
```

`pki_intermediate.csr`ファイルを見ると CSR が生成されていることがわかるでしょう。次にこの CSR に対して、先ほど作った Root CA を使ってサインをしていきます。

```shell
$ vault write -format=json pki_root/root/sign-intermediate \
csr=@pki_intermediate.csr \
format=pem_bundle ttl="12h" \
| jq -r '.data.certificate' > ca_intermediate.cert.pem
```

Root CA によって CSR がサインされ、中間 CA としての証明書が発行されました。証明書を検証してみましょう。

``` shell
$ openssl x509 -in ca_intermediate.cert.pem -text -noout
```

`CA Issuers - URI:http://127.0.0.1:8200/v1/pki_root/ca`となっており、Vault の Root CA で発行されたことがわかります。


この証明書を中間 CA にインポートします。

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

これで Root CA と Intermediate CA の準備が出来ました。最後に証明書を発行していきます。発行する前にロールを定義する必要があります。

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

例えば AWS にインポートするときは以下のように実行します。

```
aws acm import-certificate \
--certificate file://./server.crt.pem \
--private-key file://./private.key.pem \
--certificate-chain file://./ca-chain.crt.pem
```

最後に certificate の出力結果を`server.crt.pem`として保存をして証明書を検証してみます。

```shell
openssl x509 -in server.cert.pem  -text -noout
```

正しく発行されているでしょう。Vault ではこのように Root CA、Intermediate CA として Vault を扱う、もしくは既存の Root CA と Vault 上の Intermediate CA を連携させて、TTL 付きの証明書を権限に応じて動的に、迅速に発行することが可能です。

## 参考リンク
* [PKI Secret Engine](https://www.vaultproject.io/docs/secrets/pki/index.html)
* [PKI Secret Engine API](https://www.vaultproject.io/api/secret/pki/index.html)
* [PKI Roles](https://www.vaultproject.io/api/secret/pki/index.html#create-update-role)