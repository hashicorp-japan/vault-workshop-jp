# Secret Engine: KV

ここでは非常にシンプルな Key Value Store 型のシークレットエンジンを使ってみます。KV シークレットエンジンは`-dev`モードだとデフォルトでオンになっていますが、プロダクションモードだと明示的にオンにする必要があります。

## KV シークレットエンジンを有効化

Vault では各シークレットエンジンを有効化するために`enable`の処理を行います。`enable`は特定の権限を持ったトークンのみが実施できるようにすべきですが、ここでは root token を使います。ポリシーについては後ほど扱います。

```console
$ export VAULT_ADDR="http://127.0.0.1:8200"
$ vault secrets enable -path=kv -version=2 kv
Success! Enabled the kv secrets engine at: kv/

$ vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_e3aa0798    per-token private secret storage
identity/     identity     identity_86c0240d     identity store
kv/           kv           kv_12159ddb           n/a
sys/          system       system_ae51ee57       system endpoints used for control, policy and debugging
```

`kv`が有効化され、`kv/`が API のエンドポイントとしてマウントされました。以降はこのパスを利用して KV データを扱っていきます。

## KV データのライフサイクル

先ほどと同様、データを put してみましょう。

```console
$ vault kv put kv/iam name=kabu password=passwd
$ vault kv get kv/iam                                            
====== Data ======
Key         Value
---         -----
name        kabu
password    passwd
```

### データの更新
データの更新には 2 通りの方法があります。

まずは上書きしてデータのバージョンを上げる方法です。
```console
$ vault kv enable-versioning kv
$ vault kv get kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:00:44.023139Z
deletion_time    n/a
destroyed        false
version          1

====== Data ======
Key         Value
---         -----
name        kabu
password    passwd
```

`enable-versioning`をするとメタデータが付与され、バージョン管理されます。データを上書きしてバージョン 2 を作ってみます。

```console
$ vault kv put kv/iam name=kabu-2 password=passwd
Key              Value
---              -----
created_time     2019-07-12T06:08:03.871067Z
deletion_time    n/a
destroyed        false
version          2

$ vault kv get kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:08:03.871067Z
deletion_time    n/a
destroyed        false
version          2

====== Data ======
Key         Value
---         -----
name        kabu-2
password    passwd
```

データが上書きされてバージョン 2 のデータが生成されました。古いバージョンのデータは`-version`オプションを付与することで参照できます。

```console
$ vault kv get -version=1 kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:13:49.354811Z
deletion_time    n/a
destroyed        false
version          1

====== Data ======
Key         Value
---         -----
name        kabu
password    passwd
```

古いバージョンのデータを削除する際は以下の手順です。

```console
$ vault kv destroy -versions=1 kv/iam
$ vault kv get -version=1 kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:13:49.354811Z
deletion_time    n/a
destroyed        true
version          1

$ vault kv get -version=2 kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:14:08.207969Z
deletion_time    n/a
destroyed        false
version          2

====== Data ======
Key         Value
---         -----
name        kabu-2
password    passwd
```

二つ目の更新の方法は`-patch`オプションを付与する方法です。先ほどの上書きの方法だと、キーを忘れてアップデートするとどうなるか試してみましょう。

```console
$ vault kv put kv/iam password=passwd-2

Key              Value
---              -----
created_time     2019-07-12T06:19:28.028113Z
deletion_time    n/a
destroyed        false
version          3

$ vault kv get kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:19:28.028113Z
deletion_time    n/a
destroyed        false
version          3

====== Data ======
Key         Value
---         -----
password    passwd-2
```

このようにキーの存在ごと上書きされてしまいます。つぎに`patch`オプションを使ってみます。まずはデータを戻します。

```console
$ vault kv put kv/iam name=kabu-2 password=passwd
Key              Value
---              -----
created_time     2019-07-12T06:21:38.791328Z
deletion_time    n/a
destroyed        false
version          4

$ vault kv get kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:21:38.791328Z
deletion_time    n/a
destroyed        false
version          4

====== Data ======
Key         Value
---         -----
name        kabu-2
password    passwd
```

データの一部を更新してみましょう。

```console
$ vault kv patch kv/iam password=passwd-2
$ vault kv get kv/iam
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:25:39.688255Z
deletion_time    n/a
destroyed        false
version          5

====== Data ======
Key         Value
---         -----
name        kabu-2
password    passwd-2
```
`patch`を使うとデータの一部のみを更新できます。

最後にデータを削除します。

```console
$ vault kv delete kv/iam
$ vault kv metadata delete kv/iam
```

## 参考リンク
* [Vault KV Secret Engine](https://www.vaultproject.io/docs/secrets/kv/kv-v2.html)
* [vault kv command](https://www.vaultproject.io/docs/commands/kv/patch.html)
* [API Document](https://www.vaultproject.io/api/secret/kv/index.html)
