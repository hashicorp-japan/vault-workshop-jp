# 多要素認証(Multi Factor Authentication)を試す

Table of Contents
=================

  * [Policyの設定を行う](#policyの設定を行う)
  * [TOTP用のバーコードとURLを発行する](#totp用のバーコードとurlを発行する)
  * [Vaultを利用してTOTPを発行する](#vaultを利用してtotpを発行する)
  * [Google Authenticatorを利用してTOTPを発行する](#google-authenticatorを利用してtotpを発行する)
  * [参考リンク](#参考リンク)

HashiCorp Vault Enterpriseでは`Multi Factor Authentication(MFA)`
を利用して、VaultのAPIコール時に多要素での認証を設定することが可能です。

以下のような認証方式を入れることができます。

* TOTP
* Okta
* Duo
* PingID

今回はTOTPを使って時間制限付きのワンタイムパスワードを多要素認証として利用し、「Vault Tokenを作るためのAPIの実行」に対して多要素認証を掛けたいと思います。

* GitHubで認証
* 認証されたユーザにVault Tokenを作るための権限を付与
* API実行時に`TOTP`を入力し実行

という流れです。

`Multi Factor Authentication`はEnterprise版のみ有効な機能です。利用の際は[トライアルのライセンス](https://www.hashicorp.com/products/vault/trial/)やEntperpriseの正式なライセンスで機能をアクティベーションする必要があります。

ライセンスのセットの仕方は[こちら](https://www.vaultproject.io/api-docs/system/license)を参考にしてみてください。

## Policyの設定を行う

多要素認証を扱うにはVaultのPolicy設定に`mfa_methods`を付与します。`mfa_methods`で指定する値は多要素認証の方法を定義しますが、こちらを事前に定義します。

```sh
$ vault write sys/mfa/method/totp/my_totp \
    issuer=Vault \
    period=90 \
    algorithm=SHA256 \
    digits=8
```

このコマンドを実行することでTOTP MFAの設定が完了です。

* `issuer`は任意の発行者名
* `period`はTOTPの生存期間
* `algorithm`はTOTPを生成する際のアルゴリズム
* `digits`はTOTPの文字列数です。

これをポリシーの`mfa_methods`に下記のように指定します。

```hcl
path "auth/token/create" {
  capabilities = ["create"]
  mfa_methods  = ["my_totp"]
}
```

`auth/token/create`のエンドポイントに`write`処理を実行するための権限で`mfa_methods`として`my_totp`をセットしています。

以下のコマンドでセットしてみましょう。

```sh
$ vault policy write totp-policy -<<EOF
path "auth/token/create" {
  capabilities = [ "read", "list", "create", "update", "delete"]
  mfa_methods  = ["my_totp"]
}
EOF
```

## GitHub認証の設定

GitHubの認証には`Organization`, `Team`と`GitHub用のAPI Token`が必要です。それぞれ事前に作成してください。

ここでは

* `Organization` = `hashicorp-japan`
* `Team` = `vault-token-creation`

としています。

以下のコマンドでGitHub認証を有効化します。

```sh
$ ORG=<YOUR_ORG_NAME>
$ vault auth enable github
$ vault write auth/github/config organization=${ORG}
$ vault write auth/github/map/teams/vault-token-creation value=totp-policy
```

`hashicorp-japan`内の`vault-token-creation`に所属しているユーザが認証されると、先ほど作成した`totp-policy`が付与されます。

このポリシー先ほど設定した通り`auth/token/create`の`write`処理だけの権限を持ち、実行時に多要素認証を求められます。

それではログインしてみましょう。

```sh
$ vault login -method=github
```

GitHubのトークンを入力すると認証が成功し以下のように出力されるはずです。

```
GitHub Personal Access Token (will be hidden):
WARNING! The VAULT_TOKEN environment variable is set! This takes precedence
over the value set by this command. To use the value set by this command,
unset the VAULT_TOKEN environment variable or set it to the token displayed
below.

Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                    Value
---                    -----
token                  s.H4Nj8UqTXsZWGmWstkczVnMF
token_accessor         UtSrKvGDhHctNbpRCtdgu6BI
token_duration         768h
token_renewable        true
token_policies         ["default" "totp-policy"]
identity_policies      []
policies               ["default" "totp-policy"]
token_meta_org         hashicorp-japan
token_meta_username    tkaburagi
```

トークンが一つ作成され、ポリシーが設定セットされているはずです。このトークンをテストしてみましょう。

```console
$ VTOKEN=s.H4Nj8UqTXsZWGmWstkczVnMF
$ VAULT_TOKEN=${VTOKEN} vault read sys/mounts

Error listing secrets engines: Error making API request.

URL: GET http://127.0.0.1:8200/v1/sys/mounts
Code: 403. Errors:

* 1 error occurred:
	* permission denied

$ VAULT_TOKEN=${VTOKEN} vault write -f auth/token/create

Error writing data to http://127.0.0.1:8200/v1/auth/token/create: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/http:/127.0.0.1:8200/v1/auth/token/create
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

いずれのリクエストも`permission denied`となるはずです。

* `sys/mounts`にはそもそも権限がないこと
* `auth/token/create`には権限があるが、MFAがポリシー上要求されているがセットされていないこと

が原因です。

次にTOTPの発行を有効にしMFAを使ってAPIを実行してみましょう。

## TOTP用のバーコードとURLを発行する

次にTOTP用のバーコードとURLを発行します。

以下のコマンドで先ほど発行したVaultトークンの`entity_id`を取得し、`sys/mfa/method/totp/my_totp/admin-generate`のエンドポイントを実行し`barcode`, `url`を取得します。

```sh
$ vault write sys/mfa/method/totp/my_totp/admin-generate \
    entity_id=$(vault token lookup -format=json ${VTOKEN} | jq -r '.data.entity_id')
```

ここで出力された`barcode`や`url`は外部のTOTPコードのGneratorにセットすることでTOTPを発行することができます。

`barcode`と`url`を保存し、まずは`barcode`を利用して`Google Authenticator`を利用する例を紹介します。


## Google Authenticatorを利用してTOTPを発行する

まずはGoogle Authentiationを試してみます。AppStoreもしくはGoogle Playからインストールをした上で実行してください。

```sh
$ base64 --decode <<< <TOTP_BARCODE> > barcode-totp.png
```

以下のようなQRコードが生成されているはずです。

<kbd>
  <img src="https://blog-kabuctl-run.s3-ap-northeast-1.amazonaws.com/20200426/mfa-2.png">
</kbd>

これをGoogle Authenticatorでスキャンすると、以下のようにTOTPが発行されていることがわかるでしょう。

<kbd>
  <img src="https://blog-kabuctl-run.s3-ap-northeast-1.amazonaws.com/20200426/mfa-1.jpg">
</kbd>

この値をメモしてAPIを再度実行してみます。MFAを利用する際は`-mfa my_totp:<TOTP>`のパラメータをセットしAPIを実行します。

```console
$ VAULT_TOKEN=${VTOKEN} vault write -mfa my_totp:83501485 -f auth/token/create

Key                  Value
---                  -----
token                s.5nWNLFCMX9ZAcfsdBHFo184L
token_accessor       rPHpz2xsLsEdGsof50enlXWe
token_duration       768h
token_renewable      true
token_policies       ["default" "totp-policy"]
identity_policies    []
policies             ["default" "totp-policy"]
```

トークンが発行できるはずです。試しに適当なTOTPをセットしてみます。

```console
$ VAULT_TOKEN=${VTOKEN} vault write -mfa my_totp:99999999 -f auth/token/create

Error writing data to auth/token/create: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/auth/token/create
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

エラーとなり実行できないはずです。次に`my_totp:`に正しい値を入れて別のエンドポイントを実行してみましょう。

```console
$ VAULT_TOKEN=s${VTOKEN} vault write -mfa my_totp:60390043 -f sys/monts

Error writing data to sys/monts: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/sys/monts
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

権限でセットした通り、正しいTOTPを持っていても`auth/token/create`以外のエンドポイントは実行できません。

## Vaultを利用してTOTPを発行する

ここまでGoogle Autenticatorを利用してきましたが、最後にVault自身をGeneratorとして利用する方法を紹介します。

先ほど保存した`url`をコピーしましょう。

```sh
$ vault secrets enable totp
$ vault write totp/keys/my-key \
    url="<TOTP_URL>"
```

これでVault自体がキーを発行できるようになり、外部のサービスを使う必要がありません。

```console
$ vault read totp/code/my-key

Key     Value
---     -----
code    93346290
```

```console
$ VAULT_TOKEN=${VTOKEN} vault write -mfa my_totp:93346290 -f auth/token/create

Key                  Value
---                  -----
token                s.Ev5Gbtmwtvxb9QmTJYJ0UJ3T
token_accessor       KjhI3CBlnfJJunVYNOBRlHgw
token_duration       768h
token_renewable      true
token_policies       ["default" "totp-policy"]
identity_policies    []
policies             ["default" "totp-policy"]
```

同じようにTOTPを利用することができました。

以上のように、Vault EnterpriseのMFA機能を利用することで特定のエンドポイントに対してより安全な多要素認証を入れることができます。

今回はTOTPの例でしたが、Oktaなどその他の認証基盤と連携させることも可能です。

## 参考リンク
* [Vault Enterprise MFA Support](https://www.vaultproject.io/docs/enterprise/mfa)
* [TOTP MFA](https://www.vaultproject.io/docs/enterprise/mfa/mfa-totp)
* [MFA API](https://www.vaultproject.io/api-docs/system/mfa)
* [TOTP MFA API](https://www.vaultproject.io/api-docs/system/mfa/totp)
* [Learn: GitHub Auth Method](https://learn.hashicorp.com/vault/getting-started/authentication)
* [TOTP Secret Engine](https://www.vaultproject.io/docs/secrets/totp)