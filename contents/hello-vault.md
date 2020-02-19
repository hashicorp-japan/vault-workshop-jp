# 初めてのVault

ここではまずVaultのインストール、unsealと初めてのシークレットを作ってみます。

## Vaultのインストール

[こちら](https://www.vaultproject.io/downloads.html)のWebサイトからご自身のOSに合ったものをダウンロードしてください。

```
wget https://releases.hashicorp.com/vault/1.3.0/vault_1.3.0_linux_amd64.zip
```

パスを通します。以下はmacOSの例ですが、OSにあった手順で`vault`コマンドにパスを通します。

```shell
mv /path/to/vault /usr/local/bin
chmod +x /usr/local/bin/vault
```

新しい端末を立ち上げ、Vaultのバージョンを確認します。

```console
$ vault -version                                                                       
Vault v1.1.1+ent ('7a8b0b75453b40e25efdaf67871464d2dcf17a46')
```

これでインストールは完了です。

## 初めてのシークレット

次にVaultサーバを立ち上げ、GenericなシークレットをVaultに保存して取り出してみます。

```console
$ export VAULT_ADDR="http://127.0.0.1:8200"
$ vault server -dev
==> Vault server configuration:

             Api Address: http://127.0.0.1:8200
                     Cgo: disabled
         Cluster Address: https://127.0.0.1:8201
              Listener 1: tcp (addr: "127.0.0.1:8200", cluster address: "127.0.0.1:8201", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
               Log Level: info
                   Mlock: supported: false, enabled: false
                 Storage: inmem
                 Version: Vault v1.1.1+ent
             Version Sha: 7a8b0b75453b40e25efdaf67871464d2dcf17a46

WARNING! dev mode is enabled! In this mode, Vault runs entirely in-memory
and starts unsealed with a single unseal key. The root token is already
authenticated to the CLI, so you can immediately begin using Vault.

You may need to set the following environment variable:

    $ export VAULT_ADDR='http://127.0.0.1:8200'

The unseal key and root token are displayed below in case you want to
seal/unseal the Vault or re-authenticate.

Unseal Key: CNmWA769OVVTcyOptf3mFDPW5sVHOE4fw0yRnV7Tl74=
Root Token: s.rAc6mBZgrNwPxSky2dBJkgSd 
```

途中で出力される`Root Token`は後で使いますのでメモしてとっておきましょう。`-dev`モードで起動すると、データーストレージのコンフィグレーション等を行うことなく、プリセットされた設定で手軽に起動することが出来ます。クラスタ構成やデータストレージなど細かな設定が必要な場合には利用しません。また、デフォルトだとデータはインメモリに保存されるため、起動毎にデータが消滅します。

では、先ほど取得したトークンでログインしてみます。

```console
$ vault login                                                                                             
Token (will be hidden):
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.rAc6mBZgrNwPxSky2dBJkgSd
token_accessor       SgvDbZAFk0RU7bHvAtNCpw3B
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

現在有効になっているシークレットエンジンを見てみます。現在使っているトークンはroot権限と紐づいているため、現在有効になっている全てのシークレットにアクセスすることが可能です。

```console
$ vault secrets list 
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_65e8821b    per-token private secret storage
identity/     identity     identity_03927077     identity store
secret/       kv           kv_9d34f5e6           key/value secret storage
sys/          system       system_b2dfb5a6       system endpoints used for control, policy and debugging
```

`kv`シークレットエンジンを使って、簡単なシークレットをVaultに保存して取り出してみます。

```console
$ vault kv list secret/                         
No value found at secret/metadata

$ vault kv put secret/mypassword password=p@SSW0d
Key              Value
---              -----
created_time     2019-07-12T02:20:57.871216Z
deletion_time    n/a
destroyed        false
version          1

$ vault kv list secret/
Keys
----
mypassword

$ vault kv get secret/mypassword
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T02:20:57.871216Z
deletion_time    n/a
destroyed        false
version          1

====== Data ======
Key         Value
---         -----
password    p@SSW0d
```

また、VaultのCLIはAPIへのHTTPSのアクセスをラップしているため、全てのCLIでの操作はAPIへのcurlのリクエストに変換できます。`-output-curl-string`を使うだけです。

```console
$ vault kv list -output-curl-string secret/
curl -H "X-Vault-Token: $(vault print token)" http://127.0.0.1:8200/v1/kv/metadata?list=true
```

curlコマンドを使ったリクエストが表示されました。アプリなどのクライアントからVaultのAPIを呼ぶ時などに記述方法に迷った時などに便利です。

また、デフォルトではテーブル形式ですが様々なフォーマットで出力を得られます。

```console
$ vault kv get -format=yaml secret/mypassword    
data:
  name: kabu
  password: passwd
lease_duration: 2764800
lease_id: ""
renewable: false
request_id: 33de9c9d-1455-ca31-5571-84d69d0a0b77
warnings: null

$ vault kv get -format=json secret/mypassword                            
{
  "request_id": "15a27428-e566-186b-3a47-b66c727f5f02",
  "lease_id": "",
  "lease_duration": 2764800,
  "renewable": false,
  "data": {
    "name": "kabu",
    "password": "passwd"
  },
  "warnings": null
}
```

特定のフィールドのデータを抽出することもできます。

```console
$ vault kv get -format=json -field=password secret/mypassword
"p@SSW0d"
```

さて、Vaultにデータをputしてget出来ました。以降のセッションでその他のシークレットを扱っていきますが、「認証され」「ポシリーに基づいたトークンを取得し」「トークンを利用してシークレットにアクセスする」これが基本の流れです。

## Vaultのコンフィグレーション

一旦Vaultのサーバを停止し、次はVaultのコンフィグレーションを作成し、起動してみます。Vaultのコンフィグレーションは`HashiCorp Configuration Language`で記述します。

デスクトップに任意のフォルダーを作って、以下のファイルを作成します。ファイル名は`vault-local-config.hcl`とします。`path`は書き換えてください。

```shell 
$ mkdir vault-workshop
$ cd vault-workshop
$ cat > vault-local-config.hcl <<EOF
storage "file" {
   path = "/path/to/vault-workshop/vaultdata"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

ui = true
disable_mlock = true
EOF
```

ここではストレージ、リスナーとUIの最低限の設定をしています。その他にも[様々な設定](https://www.vaultproject.io/docs/configuration/)が出来ます。

ストレージのタイプは複数選択できますが、ここではローカルファイルを使います。実際の運用で可用性などを考慮する場合はConsulなどHAの機能が盛り込まれたストレージを使うべきです。このコンフィグを使ってVaultを再度起動してみましょう。

>下記のコマンドで起動時に"Error initializing core: Failed to lock memory: cannot allocate memory"のエラーが出る場合は以下の1行をvault-local-config.hclに追記してください。
> `disable_mlock  = true`

```console
$ vault server -config vault-local-config.hcl
WARNING! mlock is not supported on this system! An mlockall(2)-like syscall to
prevent memory from being swapped to disk is not supported on this system. For
better security, only run Vault on systems where this call is supported. If
you are running Vault in a Docker container, provide the IPC_LOCK cap to the
container.
==> Vault server configuration:

             Api Address: http://127.0.0.1:8200
                     Cgo: disabled
         Cluster Address: https://127.0.0.1:8201
              Listener 1: tcp (addr: "127.0.0.1:8200", cluster address: "127.0.0.1:8201", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
               Log Level: info
                   Mlock: supported: false, enabled: false
                 Storage: file
                 Version: Vault v1.1.1+ent
             Version Sha: 7a8b0b75453b40e25efdaf67871464d2dcf17a46

==> Vault server started! Log data will stream in below:
```
今回はプロダクションモードで起動しています。先ほどと違い、`Root Token`, `Unseal Key`は出力されません。Vaultを利用するまでに`init`と`unseal`という処理が必要です。

## Vaultの初期化処理

別の端末を立ち上げて以下のコマンドを実行してください。GUIでも同様のことが出来ますが、このハンズオンでは全てCLIを使います。

```console
$ export VAULT_ADDR="http://127.0.0.1:8200"
$ vault operator init
Unseal Key 1: E9wz16Q+6K8sHdV0G1IZNw4/xBC3b0lm28Hz0K/MyfM1
Unseal Key 2: FmP/bBJqArQ30wPDYS8GNfFUKKgUu141LtVNThrX8YyT
Unseal Key 3: K2zppWuRaDcCCCqb8NznfDw1Fp4bRXwslRoR4eTd7igz
Unseal Key 4: uxpETuMXmdwPm4AUcrusWwuHvn52A8XfGXPXwRBGajOF
Unseal Key 5: e3DwN3SOnSh/boJmCav4Ve8FOD3oSLjwywNwy+P5qrcx

Initial Root Token: s.51du1iIeam79Q5fBRBALVhRB
```

initの処理をすると、Vaultを`unseal`するためのキーと`Initial Root Token`が生成されます。試しにこの状態でログインしてみます。

```console
$ vault login                                                                         
Token (will be hidden):
Error authenticating: error looking up token: Error making API request.

URL: GET http://127.0.0.1:8200/v1/auth/token/lookup-self
Code: 503. Errors:

* error performing token check: Vault is sealed
```

エラーになるはずです。Vaultでは`sealed`という状態になっているといかに強力な権限のあるトークンを使ったとしてもいかなる操作も受け付けません。`unseal`の処理は`Unseal Key`を使います。

デフォルトだと5つのキーが生成され、そのうち3つのキーが集まると`unseal`されます。5つの`Unseal Key`の任意の3つを使ってみましょう。`vault operator unseal`コマンドを3度実行します。

```console
$ vault operator unseal                                                        
Unseal Key (will be hidden):
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       5
Threshold          3
Unseal Progress    1/3
Unseal Nonce       5ab14385-6ea9-f09b-4429-b6942c3cc005
Version            1.1.1+ent
HA Enabled         false

$ vault operator unseal
Unseal Key (will be hidden):
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       5
Threshold          3
Unseal Progress    2/3
Unseal Nonce       5ab14385-6ea9-f09b-4429-b6942c3cc005
Version            1.1.1+ent
HA Enabled         false

$ vault operator unseal
Unseal Key (will be hidden):
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    5
Threshold       3
Version         1.1.1+ent
Cluster Name    vault-cluster-a1cd882e
Cluster ID      3f7c2734-ec50-8834-e6c9-7a1c35726d4f
HA Enabled      false
``` 

3回目の出力で`Sealed`が`false`に変化したことがわかるでしょう。この状態で再度ログインします。

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

これでログインは成功です。以降の章ではこの環境を使ってハンズオンを進めていきます。

## 参考リンク
* [アーキテクチャ](https://www.vaultproject.io/docs/internals/architecture.html)
* [コンフィグレーション](https://www.vaultproject.io/docs/configuration/)
* [Seal](https://www.vaultproject.io/docs/configuration/seal/index.html)
* [シャミアの秘密鍵分散法](http://ohta-lab.jp/users/mitsugu/research/SSS/main.html)
* [vault server command](https://www.vaultproject.io/docs/commands/server.html)

