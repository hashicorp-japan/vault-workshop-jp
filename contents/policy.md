# Vault のポリシーを使ってアクセス制御する

ここでは Vault がサポートするいくつかの認証プロバイダーとの連携と、ポリシーによるアクセスコントロールを試してみます。これらの機能を使うことでクライアントとなるユーザ、ツールやアプリに対してどのリソースに対して、どの権限を与えるかというアイデンティティベースのセキュリティを設定することが出来ます。

ここまで Root Token を利用して様々なシークレットを扱ってきましたが、実際の運用では強力な権限を持つ Root Token は保持をせずに必要な時のみ生成します。通常、最低限の権限のユーザを作成し Vault を利用していきます。また認証も直接トークンで行うのではなく信頼できる認証プロバイダに委託することがベターです。

ここではその一部の方法とポリシーの設定を扱います。

## 初めてのポリシー

まず、プリセットされるポリシー一覧を確認してみましょう。ポリシーを管理するエンドポイントは`sys/policy`と`sys/policies`です。`sys`のエンドポイントには[その他にも様々な機能](https://www.vaultproject.io/api/system/index.html)が用意されています。

```console
$ export VAULT_ADDR="http://127.0.0.1:8200"
$ vault secrets enable -path=kv -version=2 kv
$ vault secrets enable -path=database database
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

`path`と指定されているのが各エンドポイントで`capablities`が各エンドポイントに対する権限を現しています。試しに`default`の権限を持つトークンを発行してみましょう。`default`にはこの前に作成した`database`への権限はないので`database`のパスへの如何なる操作もできないはずです。

```console
$ vault token create -policy=default
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

`default`の権限を持ったトークンを生成しました。このトークンをコピーします。Token を環境変数にセットしておきましょう。

```shell
$ export DEFAULT_TOKEN=s.acBPCz3lfDryfVr01RgwyTqK
$ export ROOT_TOKEN=s.51du1iIeam79Q5fBRBALVhRB
```

`database`エンドポイントにアクセスしましょう。権限がないため`permission denied`が発生します。

```console
$ VAULT_TOKEN=$DEFAULT_TOKEN vault list database/roles
Error listing database/roles/: Error making API request.

URL: GET http://127.0.0.1:8200/v1/database/roles?list=true
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

## ポリシーを作る

ポリシーは Vault のコンフィグレーションと同様`HCL`で記述します。

```shell
$ cd /path/to/vault-workshop
$ cat > my-first-policy.hcl <<EOF
path "database/*" {
  capabilities = [ "read", "list"]
}
EOF
```

作ったら`vault policy write`のコマンドでポリシーを作成します。ポリシーの作成は Root Token で実施します。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault policy write my-policy my-first-policy.hcl
Success! Uploaded policy: my-policy

$ vault policy list           
default
my-policy
root

$ vault policy read my-policy
path "database/*" {
  capabilities = [ "read", "list"]
}
```

新しいポリシーができました。このポリシーと紐づけられたトークンは`database`エンドポイントへの`read`, `list`の権限を与えられます。ではトークンを発行してみます。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault token create -policy=my-policy 
Key                  Value
---                  -----
token                s.bA9M42W41G7tF90REMDCtMeO
token_accessor       LfQCnqPOJHGqO8TplfSjTNFs
token_duration       768h
token_renewable      true
token_policies       ["default" "my-policy"]
identity_policies    []
policies             ["default" "my-policy"]
```

Vault にこのトークンを使って以下のコマンドを実行してください。

```shell
$ export MY_TOKEN=s.bA9M42W41G7tF90REMDCtMeO
```

```console
$ VAULT_TOKEN=$MY_TOKEN vault list database/roles       
Keys
----
role-handson
role-handson-2
role-handson-3

$ VAULT_TOKEN=$MY_TOKEN vault read database/roles/role-handson
Key                      Value
---                      -----
creation_statements      [CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON *.* TO '{{name}}'@'%';]
db_name                  my-mysql-database
default_ttl              1h
max_ttl                  24h
renew_statements         []
revocation_statements    []
rollbakc_statements      []

$ VAULT_TOKEN=$MY_TOKEN vault kv list kv/
Error making API request.

URL: GET http://127.0.0.1:8200/v1/sys/internal/ui/mounts/kv
Code: 403. Errors:

* preflight capability check returned 403, please ensure client's policies grant access to path "kv/"
```

Database のエンドポイントの read, list 出来てきますが kv エンドポイントには権限がないことがわかります。

次に Database エンドポイントに write の処理をしてみましょう。

```shell
$ VAULT_TOKEN=$MY_TOKEN vault write database/roles/role-handson-4 \
    db_name=mysql-handson-db \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON handson.product TO '{{name}}'@'%';" \
    default_ttl="30s" \
    max_ttl="30s"
```

エラーが出るはずです。

```
Error writing data to database/roles/role-handson-4: Error making API request.
URL: PUT http://127.0.0.1:8200/v1/database/roles/role-handson-4
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

ポリシーに設定した通り、`database`に対する`read`, `list`の処理が成功しましたが`write`の処理、`kv`に対する処理はエラーが発生したことがわかります。`deny by default`というルールのもと、指定したもの以外は全て`deny`となります。

もう少し細かいポリシーに変更してみましょう。

[ドキュメント](https://www.vaultproject.io/docs/concepts/policies.html)を見ながら`database/roles`以下の直下のすべてのリソースに対して`create`,`read`,`list`の権限があるが、`database/roles/role-handson`だけには一切アクセスできないコンフィグファイルを作ってみてください。

正解は[こちら](https://raw.githubusercontent.com/tkaburagi/vault-configs/master/policies/my-first-policy.hcl)です。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault policy write my-policy my-first-policy.hcl
$ VAULT_TOKEN=$ROOT_TOKEN vault token create -policy=my-policy -ttl=20m
```

```shell
$ export MY_TOKEN=<TOKEN_ABOVE>
```

```
$ VAULT_TOKEN=$MY_TOKEN vault list database/roles
Keys
----
role-handson
role-handson-2
role-handson-3

$ VAULT_TOKEN=$MY_TOKEN vault read database/roles/role-handson
Error reading database/roles/role-handson: Error making API request.

URL: GET http://127.0.0.1:8200/v1/database/roles/role-handson
Code: 403. Errors:

* 1 error occurred:
	* permission denied

$ VAULT_TOKEN=$MY_TOKEN vault read database/roles/role-handson-2
Key                      Value
---                      -----
creation_statements      [CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON handson.product TO '{{name}}'@'%';]
db_name                  mysql-handson-db
default_ttl              1h
max_ttl                  24h
renew_statements         []
revocation_statements    []
rollback_statements      []
```

以上のようになれば OK です。

ここまではトークン発行の権限を持つユーザから直接トークンを CLI を使って発行してきました。通常クライアントから Vault を利用する際は信頼する認証プロバイダと Vault を連携させプロバイダで認証をし適切なトークンを発行するといったワークフローを簡単に実現できます。以降の章ではその方法をいくつか紹介していきます。

## 参考リンク
* [Policy API Document](https://www.vaultproject.io/api/system/policy.html)
* [Authentication](https://www.vaultproject.io/docs/concepts/auth.html)
* [Policies](https://www.vaultproject.io/docs/concepts/policies.html)
* [OIDC Provider Configuration](https://www.vaultproject.io/docs/auth/jwt_oidc_providers.html)
