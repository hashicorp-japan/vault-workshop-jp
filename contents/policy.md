# Vaultのポリシーを使ってアクセス制御する

ここまでRoot Tokenを利用して様々なシークレットを扱ってきましたが、実際の運用では強力な権限を持つRoot Tokenは保持をせずに必要な時のみ生成します。通常、最低限の権限のユーザを作成しVaultを利用していきます。また認証も直接トークンで行うのではなく信頼できる認証プロバイダに委託することがベターです。

ここではその一部の方法とポリシーの設定を扱います。

## 初めてのポリシー

まず、プリセットされるポリシー一覧を確認してみましょう。ポリシーを管理するエンドポイントは`sys/policy`と`sys/policies`です。`sys`のエンドポイントには[その他にも様々な機能](https://www.vaultproject.io/api/system/index.html)が用意されています。

```console
$ vault list sys/policy
Keys
----
default
root
```

```console
$ vault read sys/policy/default
Key      Value
---      -----
name     default
rules    # Allow tokens to look up their own properties
path "auth/token/lookup-self" {
    capabilities = ["read"]
}

# Allow tokens to renew themselves
path "auth/token/renew-self" {
    capabilities = ["update"]
}

# Allow tokens to revoke themselves
path "auth/token/revoke-self" {
    capabilities = ["update"]
}
~~~~
```

`path`と指定されているのが各エンドポイントで`capablities`で指定されているのが各エンドポイントに対する権限を現しています。試しに`default`の権限を持つトークンを発行してみましょう。`default`にはこの前に作成した`database`への権限はないので`database`のパスへの如何なる操作もできないはずです。

```console
$ vault token create -policy=default -ttl=10m
Key                  Value
---                  -----
token                s.acBPCz3lfDryfVr01RgwyTqK
token_accessor       DnUd62Wcfwbg6eDX5Mhha0jf
token_duration       768h
token_renewable      true
token_policies       ["default"]
identity_policies    []
policies             ["default"]
```

`default`の権限を持ったトークンを10分のTTLで生成しました。このトークンをコピーして`vault login`します。

```console
$ vault login
Token (will be hidden):
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.up9r7C0hQAy6xvtDbwPL6y4L
token_accessor       dHRTUY5drNf3hWYagF6TbiCl
token_duration       9m16s
token_renewable      true
token_policies       ["default"]
identity_policies    []
policies             ["default"]
```

`database`エンドポイントにアクセスしましょう。権限がないため`permission denied`が発生します。

```console
$ vault list database/roles
Error listing database/roles/: Error making API request.

URL: GET http://127.0.0.1:8200/v1/database/roles?list=true
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

## ポリシーを作る



## 参考リンク
* [API Document](https://www.vaultproject.io/api/system/policy.html)
* [Authentication](https://www.vaultproject.io/docs/concepts/auth.html)
* [Plicies](https://www.vaultproject.io/docs/concepts/policies.html)
* 