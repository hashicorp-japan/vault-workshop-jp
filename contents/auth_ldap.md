# LDAP による認証

ここでは LDAP を用いた認証を行ってみます。


## LDAP サーバーの準備

もし、すでに利用可能な LDAP や AD などがあればそちらをご使用ください。手元に LDAP 環境がない場合、[OpenLDAP コンテナ](https://github.com/osixia/docker-openldap)などを準備ください。

ここでは、[Account などがセットアップされた LDAP 環境](https://github.com/grove-mountain/docker-ldap-server)を用います。
ワークショップ内で使用するスクリプトなどは、[準備した環境](https://github.com/hashicorp-japan/vault-workshop/tree/master/assets/auth_ldap)があるのでダウンロードしてください。


### OpenLDAP コンテナの起動

まず以下のコマンドで LDAP コンテナを起動します。
```shell
$ ./1.start_ldap_server.sh
```
`docker ps`などでコンテナが起動したことを確認ください。


### OpenLDAP コンテナとの通信確認
LDAP サーバーとの通信を確認するには、以下のコマンドを叩いてエントリーが取得できることを確認ください。以下では IT グループに所属しているユーザー一覧を表示します。


```console
$ ./3.list_it_members.sh
# extended LDIF
#
# LDAPv3
# base <cn=it,ou=um_group,dc=ourcorp,dc=com> with scope subtree
# filter: (objectclass=*)
# requesting: ALL
#

# it, um_group, ourcorp.com
dn: cn=it,ou=um_group,dc=ourcorp,dc=com
objectClass: groupOfUniqueNames
objectClass: top
cn: it
uniqueMember: cn=bob,ou=people,dc=ourcorp,dc=com
uniqueMember: cn=deepak,ou=people,dc=ourcorp,dc=com

# search result
search: 2
result: 0 Success

# numResponses: 2
# numEntries: 1
```


## LDAP auth method の設定

次に Vault 側で LDAP auth method を設定します。

```shell
$ ./_2.enable_auth_ldap.sh
```

こちらの中身はこうなっています。
```shell
vault auth enable -path=ldap-um ldap

echo "Configure Unique Member group lookups"

# Using group of unique names lookups

vault write auth/ldap-um/config \
    url="${LDAP_URL}" \
    binddn="${BIND_DN}" \
    bindpass="${BIND_PW}" \
    userdn="${USER_DN}" \
    userattr="${USER_ATTR}" \
    groupdn="${GROUP_DN}" \
    groupfilter="${UM_GROUP_FILTER}" \
    groupattr="${UM_GROUP_ATTR}" \
    insecure_tls=true
```

まず、`vault auth enable`で Auth method を有効化します。
その後`vault write auth/ldap-um/config`で、LDAP サーバーとの通信に必要な設定を行っています。

`vault auth list`コマンドで LDAP 認証が作成されていることを確認ください。

```console
$ vault auth list
Path         Type        Accessor                  Description
----         ----        --------                  -----------
approle/     approle     auth_approle_4bd66d05     n/a
ldap-um/     ldap        auth_ldap_ff29eb9c        n/a
token/       token       auth_token_8c9e5cf0       token based credentials
```


## シークレットを準備

次にこのワークショップで用いるシークレットを準備します。Secret engine は KV エンジンを使用します。もし、まだ設定していない場合は以下のコマンドで KV を有効化してください。

```shell
$ vault secrets enable -path=secret kv`
```

これにより、Vault 上の/secret という Path に KV エンジンがマウントされます。

KV エンジンにシークレットを書き込みます。

```shell
$ ./_4.populage_kvs.sh
```

中身はこうなっています。

```shell
#!/bin/bash

vault write secret/ldap/it password="foo"
vault write secret/ldap/security password="bar"
vault write secret/ldap/engineering password="hoge"
```

IT グループ向け、Security グループ向け、Engineering グループ向けの３つのシークレットが書き込まれました。


## Policy の設定

次に、これらのシークレットへのアクセスを許可するための Policy を準備します。


### Policy の中身
ここでは以下の IT グループ向けと Security グループ向けの２種類の Policy を使用します。

IT グループ向け (it_policy.hcl)：
```Hashicorp Configuration Language
# Policy for IT peopld

path "secret/ldap" {
	capabilities = [ "list" ]
}

path "secret/ldap/it" {
	capabilities = [ "create", "read", "update", "delete", "list" ]
}
```

Security グループ向け (security_policy.hcl)：
```Hashicorp Configuration Language
# Policy for security people

path "secret/ldap" {
	capabilities = [ "list" ]
}

path "secret/ldap/security" {
	capabilities = [ "create", "read", "update", "delete", "list" ]
}
```

それぞれの Policy に、secret/ldap 以下のそれぞれのシークレットへのアクセス権限が明示的に記載されています。


### Policy の設定とグループへの適用

Policy が準備できたら、その Policy を LDAP 上のグループと紐付けます。

```
$ ./5.write_associate_policy.sh
```

中身はこうなっています。

```shell
# create policies
vault policy write it_policy it_policy.hcl
vault policy write security_policy security_policy.hcl

# set up uniqueMember group logins
vault write auth/ldap-um/groups/it policies=it_policy
vault write auth/ldap-um/groups/security policies=security_policy
```

`vault policy write`で Policy を書き込み、`vault write auth/ldap-um/groups/<グループ名>`でグループと Policy を紐付けます。



## LDAP 認証をもちいたログイン

これで Vault を通じて LDAP 認証を行う準備が整いました。

まず、IT グループのメンバーでログインしてみます。

```console
$ ./6.login_it_member.sh
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                    Value
---                    -----
token                  s.E9OVOHtCWsCHCxnf0uggkTeO
token_accessor         yAPrXcBwrEOW1aPHjkZqzgqB
token_duration         768h
token_renewable        true
token_policies         ["default" "it_policy"]
identity_policies      []
policies               ["default" "it_policy"]
token_meta_username    deepak
```

無事にログインされ Token が返ってきています。token_policies に"it_policy"が設定されていることを確認ください。
また、`vault token lookup`で現在の Token を確認できます。

上記の token を保管してください。この例では、`s.E9OVOHtCWsCHCxnf0uggkTeOga`がそれに当たります。

同様に Security グループでのログインも行ってください。

```console
$ ./7.login_security_member.sh
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                    Value
---                    -----
token                  s.EswSipV6qpy0UEZ6Xoxdoo7X
token_accessor         7L9pwEUOyDsbfwXczefii6Vq
token_duration         768h
token_renewable        true
token_policies         ["default" "security_policy"]
identity_policies      []
policies               ["default" "security_policy"]
token_meta_username    eve
```

この Token 値も保管してください。
この後の作業では、これらの Token を切り替えて作業していきます。Token の切り替えは、`vault login <Token値>`で行います。

```shell
$ vault login s.E9OVOHtCWsCHCxnf0uggkTeOga` # 上記のITグループのTokenを使用
```

Token は環境変数(VAULT_TOKEN)
)からも設定できます。よって、以下のような切り替えも可能です。
```shell
$ export IT_TOKEN=s.E9OVOHtCWsCHCxnf0uggkTeO  # ITトークンの変数
$ export SECURITY_TOKEN=s.EswSipV6qpy0UEZ6Xoxdoo7X　# Securityトークンの変数

$ VAULT_TOKEN=$IT_TOKEN vault <コマンド>  # コマンドをITトークンで実行
$ VAULT_TOKEN=$SECURITY_TOKEN vault <コマンド>  # コマンドをSecurityトークンで実行
```


## シークレットの取得

それではシークレットの取得をしてみましょう。

まず、Policy によれば IT グループのユーザーは secret/ldap/it にはアクセスができるはずです。

```console
$ VAULT_TOKEN=$IT_TOKEN vault read secret/ldap/it
Key                 Value
---                 -----
refresh_interval    768h
password            foo
```

無事にシークレットを取得できました。
次に Security グループのシークレットの取得も試してみましょう。

```console
$ VAULT_TOKEN=$IT_TOKEN vault read secret/ldap/security
Error reading secret/ldap/security: Error making API request.

URL: GET http://127.0.0.1:8200/v1/secret/ldap/security
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

IT グループの Policy では secret/ldap/security へのアクセス権限がないので無事にはじかれました。

同様に Security グループの Token でも試してみてください。



## 参考リンク
* [LDAP auth method](https://www.vaultproject.io/docs/auth/ldap.html
)
* [API doc](https://www.vaultproject.io/api/auth/ldap/index.html)
