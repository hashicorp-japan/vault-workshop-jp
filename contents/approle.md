## AppRoleによる認証

さて、ここまではトークン発行の権限を持つユーザ(今回の場合はroot)を使ってトークンを発行してきました。

Vaultでは信頼する認証プロバイダで認証をし適切なトークンを発行するといったワークフローを簡単に実現できます。

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

まずはポリシーを作ってみましょう。今回は先ほど作った`kv`のデータにアクセスできるようなポリシーを作ってみます。

```shell
$ cat > my-approle-policy.hcl <<EOF
path "kv/*" {
  capabilities = [ "read", "list", "create", "update", "delete"]
}
EOF
```

```shell
$ VAULT_TOKEN=$ROOT_TOKEN vault policy write my-approle path/to/my-approle-policy.hcl
```

`approle`を`enable`にし、`my-approle`のポリシーに基づいたAppRoleを一つ作成します。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault auth enable approle
$ VAULT_TOKEN=$ROOT_TOKEN vault write -f auth/approle/role/my-approle policies=my-approle
$ VAULT_TOKEN=$ROOT_TOKEN vault read auth/approle/role/my-approle

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
$ VAULT_TOKEN=$ROOT_TOKEN vault read auth/approle/role/my-approle/role-id
Key        Value
---        -----
role_id    a25b3148-7b95-57bf-bc5d-cb72ffc08e68
```

次に`Secret ID`を取得しますが、いくつかの方法があります。

一つは`push`と呼ばれる方法で、カスタムの値を指定するパターンです。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault write -f auth/approle/role/my-approle/custom-secret-id secret_id=ZeCletlb
Key                   Value
---                   -----
secret_id             ZeCletlb
secret_id_accessor    c2b12a4a-0fbf-45ce-b135-be2c1d829b06
```

push型はカスタムの値をして出来ますが、Vault以外のサーバ、アプリやツールなどSecret IDを発行する側にSecret IDを知らせてしまうことになるため、通常使用しません。`pull`と呼ばれる方法が一般的です。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault write -f auth/approle/role/my-approle/secret-id
Key                   Value
---                   -----
secret_id             1cef3c1e-feca-99d8-ecd4-7a17ca997919
secret_id_accessor    f620512c-e9e9-4f84-bbf6-9f4d484ff2bc
```

この場合、クライアントに値を持たせることがなくSecret IDの発行が可能となりよりセキュアです。

これらを使って認証し、トークンを取得してみましょう。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault write auth/approle/login role_id="a25b3148-7b95-57bf-bc5d-cb72ffc08e68" secret_id="1cef3c1e-feca-99d8-ecd4-7a17ca997919"
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

AppRoleにより認証され、発行されたトークンを試してみましょう。

```shell
$ export MY_TOKEN=s.nEolH5Pjqf3207KljT9xoamS
```

```shell
VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -version=2 kv
VAULT_TOKEN=$ROOT_TOKEN vault kv put kv/iam password=p@SSW0d
```


```console
$ VAULT_TOKEN=$MY_TOKEN vault kv get kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-09-05T02:02:17.120801Z
deletion_time    n/a
destroyed        false
version          1

====== Data ======
Key         Value
---         -----
password    p@SSW0d2

$ VAULT_TOKEN=$MY_TOKEN vault read database/roles/role-demoapp
Error reading database/roles/role-demoapp: Error making API request.

URL: GET http://127.0.0.1:8200/v1/database/roles/role-demoapp
Code: 403. Errors:

* 1 error occurred:
  * permission denied
```

よりセキュアにSecret IDを扱う際は`Response Wrapping`という機能を利用しますが、これについては以降の章で扱います。また、以下のようなワークフローに組み込みより安全にIDの発行を行うことができます。

![](https://learn.hashicorp.com/assets/images/vault-approle-workflow2.png)

ref: [https://learn.hashicorp.com/vault/identity-access-management/iam-authentication](https://learn.hashicorp.com/vault/identity-access-management/iam-authentication)

##　参考リンク
* [AppRole API Document](https://www.vaultproject.io/api/auth/approle/index.html)
* [AppRole Auth Method](https://www.vaultproject.io/docs/auth/approle.html)