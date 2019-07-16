# Secret Engine: KV

ここでは非常にシンプルなKey Value Store型のシークレットエンジンを使ってみます。KVシークレットエンジンは`-dev`モードだとデフォルトでオンになっていますが、プロダクションモードだと明示的にオンにする必要があります。

## KVシークレットエンジンを有効化

Vaultでは各シークレットエンジンを有効化するために`enable`の処理を行います。`enable`は特定の権限を持ったトークンのみが実施できるようにすべきですが、ここではroot tokenを使います。ポリシーについては後ほど扱います。

```console
$ vault secrets enable -path=kv kv
Success! Enabled the kv secrets engine at: kv/

$ vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_e3aa0798    per-token private secret storage
identity/     identity     identity_86c0240d     identity store
kv/           kv           kv_12159ddb           n/a
sys/          system       system_ae51ee57       system endpoints used for control, policy and debugging
```

`kv`が有効化され、`kv/`がAPIのエンドポイントとしてマウントされました。以降はこのパスを利用してKVデータを扱っていきます。

## KVデータのライフサイクル

先ほどと同様、データをputしてみましょう。

```console
$ vault kv put kv/iam name=kabu password=passwd
$ vault kv get kv/iam                                            
====== Data ======
Key         Value
---         -----
name        kabu
password    passwd
```

また、デフォルトではテーブル形式ですが様々なフォーマットで出力を得られます。

```console
$ vault kv get -format=yaml kv/iam    
data:
  name: kabu
  password: passwd
lease_duration: 2764800
lease_id: ""
renewable: false
request_id: 33de9c9d-1455-ca31-5571-84d69d0a0b77
warnings: null

$ vault kv get -format=json kv/iam                             
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
$ vault kv get -format=json -field=name kv/iam
"kabu"
```

### データの更新
データの更新には2通りの方法があります。


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

`enable-versionin`をするとメタデータが付与され、バージョン管理されます。データを上書きしてバージョン2を作ってみます。

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

データが上書きされてバージョン2のデータが生成されました。古いバージョンのデータは`-version`オプションを付与することで参照できます。

```console
$ vault kv get -version=1 kv/
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
$ vault kv get -version=1 kv/
====== Metadata ======
Key              Value
---              -----
created_time     2019-07-12T06:13:49.354811Z
deletion_time    n/a
destroyed        true
version          1

$ vault kv get -version=2 kv/
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
$ vault kv put kv/iam password=passwd-2                                                                                                kabu@/Users/kabu/hashicorp/vault
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
$ vault kv patch kv/iam password=passwd
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