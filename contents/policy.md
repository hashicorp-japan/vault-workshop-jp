# Vaultのポリシーを使ってアクセス制御する

ここではVaultがサポートするいくつかの認証プロバイダーとの連携と、ポリシーによるアクセスコントロールを試してみます。これらの機能を使うことでクライアントとなるユーザ、ツールやアプリに対してどのリソースに対して、どの権限を与えるかというアイデンティティベースのセキュリティを設定することが出来ます。

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

`path`と指定されているのが各エンドポイントで`capablities`が各エンドポイントに対する権限を現しています。試しに`default`の権限を持つトークンを発行してみましょう。`default`にはこの前に作成した`database`への権限はないので`database`のパスへの如何なる操作もできないはずです。

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

新しいポリシーを登録してみましょう。`default`のポリシーにはポリシーを作る権限はないためrootでログインをし直します。今回は一番最初に取得したRoot Tokenを入力してください。

```console
$ vault login
Token (will be hidden):
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.51du1iIeam79Q5fBRBALVhRB
token_accessor       z28eqFezRCtIlaH33OSnhEGt
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

ポリシーはVaultのコンフィグレーションと同様`HCL`で記述します。以下のファイルを`my-first-policy.hcl`というファイル名で作ってください。
```hcl
path "database/*" {
  capabilities = [ "read", "list"]
}
```

作ったら`vault policy write`のコマンドでポリシーを作成します。

```console
$ vault policy write my-policy ~/my-first-policy.hcl
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
$ vault token create -policy=my-policy 
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

Vaultにこのトークンを使ってログインし、以下のコマンドを実行してください。

```console
$ vault login s.bA9M42W41G7tF90REMDCtMeO
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.bA9M42W41G7tF90REMDCtMeO
token_accessor       LfQCnqPOJHGqO8TplfSjTNFs
token_duration       767h59m33s
token_renewable      true
token_policies       ["default" "my-policy"]
identity_policies    []
policies             ["default" "my-policy"]

$ vault list database/roles       
Keys
----
my-role
role-handson
role-handson-2
role-handson-3

$ vault read database/roles/my-role
Key                      Value
---                      -----
creation_statements      [CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON *.* TO '{{name}}'@'%';]
db_name                  my-mysql-database
default_ttl              1h
max_ttl                  24h
renew_statements         []
revocation_statements    []
rollbakc_statements      []

$ vault kv list kv/
Error making API request.

URL: GET http://127.0.0.1:8200/v1/sys/internal/ui/mounts/kv
Code: 403. Errors:

* preflight capability check returned 403, please ensure client's policies grant access to path "kv/"

$ vault write database/roles/role-handson-4 \
    db_name=mysql-handson-db \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON handson.product TO '{{name}}'@'%';" \
    default_ttl="30s" \
    max_ttl="30s"
Error writing data to database/roles/role-handson-4: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/database/roles/role-handson-4
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

ポリシーに設定した通り、`database`に対する`read`, `list`の処理が成功しましたが`write`の処理、`kv`に対する処理はエラーが発生したことがわかります。`deny by default`というルールのもと、指定したもの以外は全て`deny`となります。

もう少し細かいポリシーに変更してみましょう。

ルートトークンでログインし直します。

```console
$ vault login s.51du1iIeam79Q5fBRBALVhRB
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.51du1iIeam79Q5fBRBALVhRB
token_accessor       z28eqFezRCtIlaH33OSnhEGt
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

[ドキュメント](https://www.vaultproject.io/docs/concepts/policies.html)を見ながら`database/roles`以下の直下のすべてのリソースに対して`create`,`read`,`list`の権限があるが、`database/roles/role-handson`だけには一切アクセスできないコンフィグファイルを作ってみてください。

正解は[こちら](https://raw.githubusercontent.com/tkaburagi/vault-configs/master/policies/my-first-policy.hcl)です。

```console
$ vault policy write my-policy ~/hashicorp/vault/configs/policies/my-first-policy.hcl
$ vault token create -policy=my-policy -ttl=20m
$ vault login <TOKEN>
$ vault list database/roles
Keys
----
my-role
role-handson
role-handson-2
role-handson-3

$ vault read database/roles/role-handson
Error reading database/roles/role-handson: Error making API request.

URL: GET http://127.0.0.1:8200/v1/database/roles/role-handson
Code: 403. Errors:

* 1 error occurred:
	* permission denied

$ vault read database/roles/role-handson-2
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

以上のようになればOKです。さて、ここまではトークン発行の権限を持つユーザ(今回の場合はroot)を使ってトークンを発行してきました。

Vaultでは信頼する認証プロバイダで認証をし適切なトークンを発行するといったワークフローを簡単に実現できます。

## 認証プロバイダの設定

Vaultでは以下のような認証プロバイダに対応しています。

* AppRole
* AliCloud
* AWS
* Azure
* GCP
* JWT/OIDC
* Kubernetes
* GitHub
* Okta
* LDAP

GitHubとOIDCを試してみたい方はすでに丁寧なインストラクションがあるので参考リンクを確認してみてください。ここではAppRoleを試してみます。AppRoleは他の認証メソッド同様トークンを取得するための手段です。LDAPや他の認証方法が人による操作を前提としている一方AppRoleはマシンやアプリによる操作が前提とされており、自動化のワークフローに組み込みやすくなっています。

ワークフローの例は以下のようなイメージです。

![](https://learn.hashicorp.com/assets/images/vault-approle-workflow.png)
ref: [https://learn.hashicorp.com/vault/identity-access-management/iam-authentication](https://learn.hashicorp.com/vault/identity-access-management/iam-authentication)

AppRoleで認証するためには`Role ID`と`Secret ID`という二つの値が必要で、usernameとpasswordのようなイメージです。各AppRoleはポリシーに紐付き、AppRoleで承認されるとクライアントにポリシーに基づいた権限のトークンが発行されます。

まずはポリシーを作ってみましょう。今回は先ほど作った`kv`のデータにアクセスできるようなポリシーを作ってみます。`my-approle-policy.hcl`というファイル名で以下のファイルを作ってwriteしてください。

```hcl
path "kv/*" {
  capabilities = [ "read", "list", "create", "update", "delete"]
}
```

```shell
$  vault policy write my-approle path/to/my-approle-policy.hcl
```

`approle`を`enable`にし、`my-approle`のポリシーに基づいたAppRoleを一つ作成します。

```console
$ vault auth enable approle
$ vault write -f auth/approle/role/my-approle policies=my-approle
$ vault read auth/approle/role/my-approle
WARNING! The following warnings were returned from Vault:

  * The "bound_cidr_list" parameter is deprecated and will be removed in favor
  of "secret_id_bound_cidrs".

Key                      Value
---                      -----
bind_secret_id           true
bound_cidr_list          <nil>
local_secret_ids         false
period                   0s
policies                 [my-approle]
secret_id_bound_cidrs    <nil>
secret_id_num_uses       0
secret_id_ttl            0s
token_bound_cidrs        <nil>
token_max_ttl            0s
token_num_uses           0
token_ttl                0s
token_type               default
```

これでAppRoleの作成は完了です。次に`Role ID`を取得します。

```console
$ vault read auth/approle/role/my-approle/role-id
Key        Value
---        -----
role_id    a25b3148-7b95-57bf-bc5d-cb72ffc08e68
```

次に`Secret ID`を取得しますが、いくつかの方法があります。

一つは`push`と呼ばれる方法で、カスタムの値を指定するパターンです。

```console
$ vault write -f auth/approle/role/my-approle/custom-secret-id secret_id=ZeCletlb
Key                   Value
---                   -----
secret_id             ZeCletlb
secret_id_accessor    c2b12a4a-0fbf-45ce-b135-be2c1d829b06
```

push型はカスタムの値をして出来ますが、Vault以外のサーバ、アプリやツールなどSecret IDを発行する側にSecret IDを知らせてしまうことになるため、通常使用しません。`pull`と呼ばれる方法が一般的です。

```console
$ vault write -f auth/approle/role/my-approle/secret-id
Key                   Value
---                   -----
secret_id             1cef3c1e-feca-99d8-ecd4-7a17ca997919
secret_id_accessor    f620512c-e9e9-4f84-bbf6-9f4d484ff2bc
```

この場合、クライアントに値を持たせることがなくSecret IDの発行が可能となりよりセキュアです。

これらを使って認証し、トークンを取得してみましょう。

```console
vault write auth/approle/login role_id="a25b3148-7b95-57bf-bc5d-cb72ffc08e68" secret_id="1cef3c1e-feca-99d8-ecd4-7a17ca997919"
Key                     Value
---                     -----
token                   s.nEolH5Pjqf3207KljT9xoamS
token_accessor          bzRhTIXZ2GzggmDFiuDUgWJy
token_duration          768h
token_renewable         true
token_policies          ["default" "my-approle"]
identity_policies       []
policies                ["default" "my-approle"]
token_meta_role_name    my-approle-policy
```

AppRoleにより認証され、発行されたトークンを試してみましょう。`VAULT_TOKEN`をセットすると使えます。

```console
$ VAULT_TOKEN=s.nEolH5Pjqf3207KljT9xoamS vault kv get kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-15T02:02:54.166723Z
deletion_time    n/a
destroyed        false
version          3

====== Data ======
Key         Value
---         -----
name        kabu
password    passwd-2

$ VAULT_TOKEN=s.nEolH5Pjqf3207KljT9xoamS vault read database/roles/role-demoapp
Error reading database/roles/role-demoapp: Error making API request.

URL: GET http://127.0.0.1:8200/v1/database/roles/role-demoapp
Code: 403. Errors:

* 1 error occurred:
  * permission denied
```

よりセキュアにSecret IDを扱う際は`Response Wrapping`という機能を利用しますが、これについては以降の章で扱います。また、以下のようなワークフローに組み込みより安全にIDの発行を行うことができます。

![](https://learn.hashicorp.com/assets/images/vault-approle-workflow2.png)
ref: [https://learn.hashicorp.com/vault/identity-access-management/iam-authentication](https://learn.hashicorp.com/vault/identity-access-management/iam-authentication)



## 参考リンク
* [API Document](https://www.vaultproject.io/api/system/policy.html)
* [Authentication](https://www.vaultproject.io/docs/concepts/auth.html)
* [Policies](https://www.vaultproject.io/docs/concepts/policies.html)
* [OIDC Provider Configuration](https://www.vaultproject.io/docs/auth/jwt_oidc_providers.html)
* [Auth0を使ったOIDC認証](https://learn.hashicorp.com/vault/operations/oidc-auth)
* [GitHubを使った認証](https://learn.hashicorp.com/vault/getting-started/authentication)