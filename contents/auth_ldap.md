# LDAPによる認証

ここではLDAPを用いた認証を行ってみます。


## LDAPサーバーの準備

ここでは、[OpenLDAPコンテナ](https://github.com/osixia/docker-openldap)を用いてCopy&Pasteしながら、LDAP連携の挙動を確認していきます。

### OpenLDAPコンテナの起動

まず以下のコマンドでLDAPコンテナを起動します。

```shell
$ docker run -d --name openldap -p 389:389 -e LDAP_ORGANIZATION="Example corp" -e LDAP_DOMAIN="example.org" -e LDAP_ADMIN_PASSWORD="admin" osixia/openldap:1.5.0
```

`docker ps`などでコンテナが起動したことを確認ください。

### OpenLDAP環境の設定

LDAPに、`it`部門と、`security`部門を想定したグループを作成し、`it_people_1`と`it_people_2`のユーザを設定します。

まず、以下のコマンドで、LDIFファイルを作成します。

```shell
$ cat > users.ldif <<'EOF'
# ── ユーザー用 OU
dn: ou=people,dc=example,dc=org
objectClass: organizationalUnit
ou: people

# ── IT 部署ユーザー
dn: uid=it_people_1,ou=people,dc=example,dc=org
objectClass: inetOrgPerson
cn: IT Person One
sn: One
uid: it_people_1
userPassword: pass-it

# ── セキュリティ部署ユーザー
dn: uid=security_people_1,ou=people,dc=example,dc=org
objectClass: inetOrgPerson
cn: Security Person One
sn: One
uid: security_people_1
userPassword: pass-sec

# ── グループ用 OU
dn: ou=groups,dc=example,dc=org
objectClass: organizationalUnit
ou: groups

# ── IT グループ（メンバー：it_people_1）
dn: cn=it,ou=groups,dc=example,dc=org
objectClass: groupOfNames
cn: it
member: uid=it_people_1,ou=people,dc=example,dc=org

# ── セキュリティグループ（メンバー：security_people_1）
dn: cn=security,ou=groups,dc=example,dc=org
objectClass: groupOfNames
cn: security
member: uid=security_people_1,ou=people,dc=example,dc=org
EOF
```

users.ldifファイルが作成された事を確認したら、稼働中のコンテナにLDIFファイルのコピーを行います。

```shell
% docker cp users.ldif openldap:/tmp/users.ldif
```

結果として以下のような内容が表示されます。

```shell
Successfully copied 3.07kB to openldap:/tmp/users.ldif
```

LDIFファイルをコピーしたら、設定ディレクトリにコピーしてLDAPに設定を反映します。

```shell
$ docker exec -it openldap ldapadd -x -D "cn=admin,dc=example,dc=org" -w admin -f /tmp/users.ldif
```

結果として以下のような内容が表示されます。


```shell

adding new entry "ou=people,dc=example,dc=org"

adding new entry "uid=it_people_1,ou=people,dc=example,dc=org"

adding new entry "uid=security_people_1,ou=people,dc=example,dc=org"

adding new entry "ou=groups,dc=example,dc=org"

adding new entry "cn=it,ou=groups,dc=example,dc=org"

adding new entry "cn=security,ou=groups,dc=example,dc=org"
```

もし投入に失敗して途中から投入をリトライする場合には `-c` オプションが必要となります。
修正して設定をLDAP設定をやりなおす場合、再びLDIFファイルをコピーした上で、以下のコマンドを試してください。

```shell
$ dokcer exec -it openldap ldapadd -c -x -D "cn=admin,dc=example,dc=org" -w admin -f /tmp/users.ldif
```


### OpenLDAPコンテナとの通信確認
LDAPサーバーとの通信を確認するには、以下のコマンドを叩いてエントリーが取得できることを確認ください。

コマンドとしては、 `-D` には、バインドDNとしてadminユーザでLDAPにログインする事を指定しています。検索クエリとして設定されいてる `(&(A)(B))` は論理積（AND条件）で、 `(obujectClass=groupOfNames)` でグループオブジェクトである事と、 `(cn=valut-users)` でグループ名がit（もしくはsecurity）であることを指定して検索しています。

以下ではITグループに所属しているユーザー一覧を表示します。
`-b` には検索起点となるベースDNを設定 `"dc=example,dc=org"` としてexample.comを指定しています。

```shell
$ docker exec -it openldap ldapsearch -x -D "cn=admin,dc=example,dc=org" -w admin -b "dc=example,dc=org" "(&(objectClass=groupOfNames)(cn=it))" -LLL cn member
```

結果として以下のような内容が表示されます。

```shell
dn: cn=it,ou=groups,dc=example,dc=org
cn: it
member: uid=it_people_1,ou=people,dc=example,dc=org
```

以下ではSecurityグループに所属しているユーザー一覧を表示します。

```shell
$ docker exec -it openldap ldapsearch -x -D "cn=admin,dc=example,dc=org" -w admin -b "dc=example,dc=org" "(&(objectClass=groupOfNames)(cn=security))" -LLL cn member
```

結果として以下のような内容が表示されます。

```shell
dn: cn=security,ou=groups,dc=example,dc=org
cn: security
member: uid=security_people_1,ou=people,dc=example,dc=org
```


## LDAP auth methodの設定

次にVault側でLDAP auth methodを設定します。

```shell
$ vault auth enable -path=ldap ldap
```

結果として以下のような内容が表示されます。

```shell
Success! Enabled ldap auth method at: ldap/
```

Vaultに、LDAPの設定内容に沿った設定を投入します。コマンドの前に解説すると以下の様な内容となっています。

```
# LDAPサーバーのURL
url      = "ldap://127.0.0.1:389"

# LDAPに接続するための管理者アカウント(DN)とパスワード
binddn   = "cn=admin,dc=example,dc=org"
bindpass = "admin"

# ユーザーが格納されているベースDN
userdn   = "ou=people,dc=example,dc=org"

# Vaultにログインする際に使用するユーザー属性
# ここではLDAP設定上の "uid" をログイン名として利用する
userattr = "uid"

# グループが格納されているベースDN
groupdn  = "ou=groups,dc=example,dc=org"

# グループに属しているかを確認するフィルタ
# {{.UserDN}} がログイン中のユーザーDNに置き換えられる
groupfilter = "(&(objectClass=groupOfNames)(member={{.UserDN}}))"

# VaultがLDAP設定上のグループ名として利用する属性
groupattr   = "cn"

# TLS証明書の検証を無効化（テスト用途のみ）
insecure_tls = true
```

上記の内容をvaultに設定するコマンドは以下の通りです。
LDAPサーバーとの通信に必要な設定を行っています。

```shell
$ vault write auth/ldap/config -<< EOH
{
"url":"ldap://127.0.0.1:389",
"binddn":"cn=admin,dc=example,dc=org",
"bindpass":"admin",
"userdn":"ou=people,dc=example,dc=org",
"userattr":"uid",
"groupdn":"ou=groups,dc=example,dc=org",
"groupfilter":"(&(objectClass=groupOfNames)(member={{.UserDN}}))",
"groupattr":"cn",
"insecure_tls":true
}
EOH
```

結果として以下のような内容が表示されます。

```shell
Success! Data written to: auth/ldap/config

```

`vault auth list`コマンドでLDAP認証が作成されていることを確認ください。

```console
$ vault auth list
```

結果として以下のような内容が表示されます。

```console
Path      Type     Accessor               Description                Version
----      ----     --------               -----------                -------
ldap/     ldap     auth_ldap_d161dcdc     n/a                        n/a
token/    token    auth_token_3817a250    token based credentials    n/a
```


## シークレットを準備

次にこのワークショップで用いるシークレットを準備します。Secret engineはKVエンジンを使用します。もし、まだ設定していない場合は以下のコマンドでKVを有効化してください。

```shell
$ vault secrets enable -path=secret kv
```

これにより、Vault上の/secretというPathにKVエンジンがマウントされます。

すでに `secret` が設定されているかどうかは、以下のコマンドで確認できます。

```shell
% vault secrets list
```

結果として以下のような内容が表示されます。

```shell
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_ea802eb5    per-token private secret storage
identity/     identity     identity_db97ced7     identity store
secret/       kv           kv_826e0694           key/value secret storage
sys/          system       system_814a0e43       system endpoints used for control, policy and debugging

```


KVエンジンにIT部門用のシークレットを書き込みます。

```shell
% vault kv put secret/ldap/it password="foo"
```

結果として以下のような内容が表示されます。

```shell
=== Secret Path ===
secret/data/ldap/it

======= Metadata =======
Key                Value
---                -----
created_time       2025-09-09T10:38:29.024046Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```

KVエンジンにセキュリティ部門用のシークレットを書き込みます。

```shell
 % vault kv put secret/ldap/security password="bar"
```

結果として以下のような内容が表示されます。


```shell
====== Secret Path ======
secret/data/ldap/security

======= Metadata =======
Key                Value
---                -----
created_time       2025-09-09T10:38:46.759949Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```

ITグループ向け、Securityグループ向けの２つのシークレットが書き込まれました。


## Policyの設定

次に、これらのシークレットへのアクセスを許可するためのPolicyを準備します。


### Policyの中身
ここでは以下のITグループ向けとSecurityグループ向けの２種類のPolicyを使用します。

まずIT部門用のPolicyファイルを作成します。

```shell
$ cat > it_policy.hcl <<'EOF'
# Policy for IT people
path "secret/data/ldap" {
	capabilities = [ "list" ]
}

# For KV v2 ACL rules
# see https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/upgrade
path "secret/data/ldap/it" {
	capabilities = [ "create", "read", "update", "delete", "list" ]
}

EOF
```

次にSecurity部門用のPolicyファイルを作成します。

```shell
$ cat > security_policy.hcl <<'EOF'
# Policy for security people

path "secret/data/ldap" {
	capabilities = [ "list" ]
}

# For KV v2 ACL rules
# see https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/upgrade
path "secret/data/ldap/security" {
	capabilities = [ "create", "read", "update", "delete", "list" ]
}
EOF
```

それぞれのPolicyに、secret/ldap以下（secret/data/ldap以下）のそれぞれのシークレットへのアクセス権限が明示的に記載されています。

pathに `secret/data` から始まっている点について詳しく知りたい場合は、
https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2/upgrade
を確認してください。


### Policyの設定とグループへの適用

Policyが準備できたら、そのPolicyをLDAP上のグループと紐付けます。

まず、IT部門のPolicyを設定します。

```shell
$ vault policy write it_policy it_policy.hcl
```

結果として以下のような内容が表示されます。

```shell
Success! Uploaded policy: it_policy
```

次に、Security部門のPolicyを設定します。

```shell
$ vault policy write security_policy security_policy.hcl
```

結果として以下のような内容が表示されます。

```shell
Success! Uploaded policy: security_policy
```

設定されたIT部門用のPolicyをLDAP上のitグループと紐づけます。

```shell
$ vault write auth/ldap/groups/it policies=it_policy
```

結果として以下のような内容が表示されます。

```shell
Success! Data written to: auth/ldap/groups/it
```

設定されたsecurity部門用のPolicyをLDAP上のsecurityグループと紐づけます。

```shell
$ vault write auth/ldap/groups/security policies=security_policy
```

結果として以下のような内容が表示されます。

```shell
Success! Data written to: auth/ldap/groups/security
```


`vault policy write` でPolicyを書き込み、 `vault write auth/ldap/groups/<グループ名>` でグループとPolicyを紐付けました。



## LDAP認証を利用したログイン

これでVaultを通じてLDAP認証を行う準備が整いました。

まず、IT部門のメンバー `it_people_1` でログインしてみます。

```shell
% vault login -method=ldap -path=ldap username=it_people_1 password=pass-it
```

結果として以下のような内容が表示されます。

```shell
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                    Value
---                    -----
token                  hvs.CAESILL....
token_accessor         BxhAnmJI3EOKP2URyPOabZp8
token_duration         768h
token_renewable        true
token_policies         ["default" "it_policy"]
identity_policies      []
policies               ["default" "it_policy"]
token_meta_username    it_people_1
```


無事にログインされTokenが返ってきています。token_policiesに"it_policy"が設定されていることを確認ください。

上記のtokenを以降の確認作業に利用するため、保管してください。


次に、Security部門のメンバー `security_people_1` でログインしてみます。

```shell
% vault login -method=ldap -path=ldap username=security_people_1 password=pass-sec
```

結果として以下のような内容が表示されます。

```shell
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                    Value
---                    -----
token                  hvs.CAESIB............
token_accessor         yZZm6fucxvbF4qUNrbge9aVX
token_duration         768h
token_renewable        true
token_policies         ["default" "security_policy"]
identity_policies      []
policies               ["default" "security_policy"]
token_meta_username    security_people_1
```

こちらも無事にログインされTokenが返ってきています。token_policiesに"security_policy"が設定されていることを確認ください。

同じく、上記のtokenを以降の確認作業に利用するため、保管してください。

また、`vault token lookup` で現在のTokenを確認できます。

ここからの動作確認のため、それぞれのログインの結果出力にあるtokenを環境変数にいれておきます。

（Tokenは出力内容にあわせて差し替えてください）

```shell
$ #IT部門ユーザのtoken
$ export IT_TOKEN=hvs.CAESILL....
$ #security部門ユーザのtoken
$ export SECURITY_TOKEN=hvs.CAESIB......
```

この後の作業では、これらのTokenを切り替えて作業していきます。Tokenの切り替えは、 `vault login <Token値>` で行います。

```shell
$ vault login hvs.CAESILL....
$ # 上記のITグループユーザのTokenを使用
```

Tokenは環境変数 `VAULT_TOKEN` からも設定できます。よって、以下のような切り替えも可能です。

```shell
$ VAULT_TOKEN=$IT_TOKEN vault <コマンド>  # コマンドをITトークンで実行
$ VAULT_TOKEN=$SECURITY_TOKEN vault <コマンド>  # コマンドをSecurityトークンで実行
```


## シークレットの取得

それではシークレットの取得をしてみましょう。

まず、PolicyによればITグループのユーザーは `secret/ldap/it` にアクセスができるはずです。
（policyファイルでは `secret/data/ldap/it` を設定していますが問題なく見えるはずです。）

```shell
$ VAULT_TOKEN=$IT_TOKEN vault kv get /secret/ldap/it
```

`secret/data/ldap/it` が表示されていることが確認できます。

```shell
=== Secret Path ===
secret/data/ldap/it

======= Metadata =======
Key                Value
---                -----
created_time       2025-09-09T11:09:11.314132Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
password    foo
```

同様にSecurityグループのユーザは、 `secret/ldap/security` にアクセスできます。
（policyファイルでは `secret/data/ldap/security` を設定しています）

```shell
$ VAULT_TOKEN=$SECURITY_TOKEN vault kv get /secret/ldap/security
```

`secret/data/ldap/security` が表示されていることが確認できます。

```shell
====== Secret Path ======
secret/data/ldap/security

======= Metadata =======
Key                Value
---                -----
created_time       2025-09-09T11:09:25.600965Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
password    bar
```

ここで、IT部門ユーザで、securityのsecretの取得を試してみます。

```shell
$ VAULT_TOKEN=$IT_TOKEN vault kv get /secret/ldap/security
```

以下のように `permisson denied` が表示されて取得ができません。
policyがうまく動作しています。
ITグループのPolicyでは　`secret/ldap/security` へのアクセス権限がないので無事にはじかれました。


```shell

Error reading secret/data/ldap/security: Error making API request.

URL: GET http://127.0.0.1:8200/v1/secret/data/ldap/security
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

```shell
$ VAULT_TOKEN=$SECURITY_TOKEN vault kv get /secret/ldap/it
```

同様にセキュリティ部門ユーザは `secret/ldap/it` へのアクセス権限がないのではじかれています。
こうして、Policyの動作を確認することができました。

```shell
Error reading secret/data/ldap/it: Error making API request.

URL: GET http://127.0.0.1:8200/v1/secret/data/ldap/it
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

## 参考リンク
* [LDAP auth method](https://www.vaultproject.io/docs/auth/ldap.html
)
* [API doc](https://www.vaultproject.io/api/auth/ldap/index.html)
