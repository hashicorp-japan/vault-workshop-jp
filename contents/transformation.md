# Transform Secret Engineを試す

`Transform Secret Engine`は`Format Preserving Encryption(FPE)`と`Masking`を実現するためのシークレットエンジンです。

`Transit Secret Engine`ではランダムな値を用いて暗号化を実現しましたが、

`FPE`とは、例えば`1234-5678-8765-4321`のような入力値に対して、`ASKT-THN3-KWt9-HHOA`のようにフォーマットを維持したまま暗号化する機能です。

`Masking`とは、`1234-5678-8765-4321`のような入力値に対して、`****-****-****-****`のように値をマスキングする機能です。

`FPE`を利用することで、データサイズを変更やデータベースのスキーマの変更することなく暗号化を実現することが可能となります。

`Transform Secret Engine`はEnterprise版のみ有効な機能です。利用の際は[トライアルのライセンス](https://www.hashicorp.com/products/vault/trial/)やEntperpriseの正式なライセンスで機能をアクティベーションする必要があります。

ライセンスのセットの仕方は[こちら](https://www.vaultproject.io/api-docs/system/license)を参考にしてみてください。

## Transformationの4つのリソース

`Transform Secret Engine`では4つのリソースを利用して上記のような機能を実現します。

* `Roles`: Transformationを行うためのロール。暗号化する際のエンドポイントとなり、ACLの設定をする際にも利用される。
* `Alphabets`: 置換される平文、および暗号化された後の暗号文に含まれるUTF-8の文字列の定義する。
* `Templates`: 実際に入力値を暗号化する際に利用するテンプレート。暗号化で使用する`Alphabets`や暗号する値の`Parttern`(フォーマット)などを指定する。
* `Transformation`: 利用可能な`Roles`, 利用する`Templates`, `Type`などを定義する。

また暗号化のアルゴリズムには`NIST`によって認定されている、`AES-FF3-1`を採用しています。

## FPEを実際に使ってみる

4つのリソースを意識しながら実際にまずはあらかじめ用意されているパターンで試してみたいと思います。

まずは有効化しましょう。Secret Engineの名前は`transform`です。

```shell
$ vault secrets enable transform
```

`Alphabets`と`Templates`はデフォルトのものが用意されています。各リソースを確認してみましょう。

```console
$ vault list transform/alphabet
Keys
----
builtin/alphalower
builtin/alphanumeric
builtin/alphanumericlower
builtin/alphanumericupper
builtin/alphaupper
builtin/numeric

$ vault list transform/template
Keys
----
builtin/creditcardnumber
builtin/socialsecuritynumber
```

この中`builtin/creditcardnumber`のテンプレートを使ってみます。このテンプレートは入力されたクレジットカード番号をランダムの数字で暗号化するものです。

まず、ロールを定義します。

```shell
$ vault write transform/role/my-transform-role \
transformations=first-transform \
```

この`my-transform-role`が暗号化をするときのエンドポイントの末尾となります。

`builtin/creditcardnumber`を利用したTransformationを作成してみましょう。`transform/transformation/<Transform Name>`がエンドポイントです。

```shell
$ vault write transform/transformation/first-transform \
type=fpe \
template=builtin/creditcardnumber \
allowed_roles=my-transform-role \
tweak_source=internal
```

* `type`は現在は`fpe`, `masking`のどちらかの選択です。
* `tweak_source`は暗号化をする際にツイーク値を持たせるか否かのパラメータです。ここでは`internal`とし、内部的に持たせるものとしています。

作成した`Transformation`を見てみましょう。

```console
$ vault read transform/transformation/first-transform

Key              Value
---              -----
allowed_roles    [my-transform-role]
templates        [builtin/creditcardnumber]
tweak_source     internal
type             fpe
```

さて、これを利用して暗号化する際は`transform/encode/<Role Name>`のエンドポイントを実行し、平文を渡します。

```console
$ vault write transform/encode/my-transform-role value=1234-4321-5678-8765

Key              Value
---              -----
encoded_value    1166-5682-8535-1071
```

以上のようにランダムな数字に暗号化されました。このとき、Vaultが特定の値と値をマッピングしているわけではなく、常に`AES-FF3-1`アルゴリズムを利用して暗号化がなされています。

次に複合化してみます。

```console
$ vault write transform/decode/my-transform-role value=1166-5682-8535-1071

Key              Value
---              -----
decoded_value    1234-4321-5678-8765
```

正しい値が取り出せるでしょう。

## 自作のTransformationを利用する

次に自作の`Alphabet`と`Template`を作って暗号化をしてみましょう。ここではEmailアドレスを暗号化する`Transformation`を作ってみます。

まず`Alphabet`を作成します。ここでは置換する文字列と暗号で利用する文字列両方を指定します。

```shell
$ vault write transform/alphabet/localemailaddress \
alphabet=".@0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
```

次に`Template`です。

```shell
$ vault write transform/template/email-template \
type=regex \
pattern='([0-9A-Za-z]{1,100})@.*' \
alphabet=localemailaddress
```
テンプレートに設定する項目は下記の通りです。

* `type`: 現状はregrexのみサポート
* `pattern`: フォーマットの正規表現
* `alphabet`: 利用するアルファベット


最後に`Transformation`です。

```shell
$ vault write transform/transformations/fpe/email \
template=email-template \
allowed_roles=my-transform-role \
tweak_source=internal
```

今回はトランスフォームの名前に`email`、テンプレートに`email-template`をしてしています。

```shell
vault write transform/role/my-transform-role \
transformations=first-transform,email
```

このトランスフォームを`my-transform-role`ロールで利用可能に設定します。

それぞれの設定を確認しておきましょう。

```console
$ vault read transform/alphabet/localemailaddress
Key         Value
---         -----
alphabet    0123456789.@abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ

$ vault read transform/template/email-template
Key         Value
---         -----
alphabet    localemailaddress
pattern     ([0-9A-Za-z]{1,100})@.*
type        regex

$ vault read transform/transformation/email
Key              Value
---              -----
allowed_roles    [my-transform-role]
templates        [email-template]
tweak_source     internal
type             fpe
```

これを利用して暗号化をしてみましょう。ここで`value`で入力できる値は`localemailaddress`で指定しているアルファベットのみですので注意してください。`_`,`-`などは使えません。(もちろんアルファベットに追加すれば利用できます。)

```console
$ vault write transform/encode/my-transform-role \
value="email@kabuctl.run" \
transformation=email

Key              Value
---              -----
encoded_value    wmeph@kabuctl.run
```

複合化してみます。

```console
$ vault write transform/decode/my-transform-role \
value="wmeph@kabuctl.run" \
transformation=email

Key              Value
---              -----
decoded_value    email@kabuctl.run
```

最後に、`@`以下も暗号するように設定してみます。

テンプレートを以下のように書き直します。

```shell
$ vault write transform/template/email-template \
type=regex \
pattern='([0-9A-Za-z]{1,100})@(.*)\.(.*)' \
alphabet=localemailaddress
```

暗号化と複合化を試していましょう。`@`以下も暗号化されていることがわかるでしょう。

```console
$ vault write transform/encode/my-transform-role \
value="takayuki@kabucorp.com" \
transformation=email

Key              Value
---              -----
encoded_value    XE6TPQy7@kvcnrgrp.xce
```

```console
$ vault write transform/decode/my-transform-role \
value="XE6TPQy7@kvcnrgrp.xce" \
transformation=email
Key              Value
---              -----
decoded_value    takayuki@kabucorp.com
```

## Tweak値を利用する

ここまでTweak値を利用せず暗号化を実施してきました。より安全にデータを守るためにはツイーク値というランダムの値を暗号文とセットで持たせることができます。

ツイーク値を利用することで複合化の際に、暗号キーへのアクセスに合わせてツイーク値を要求することができます。

一番最初に作った`first-transform`で試してみましょう。

```console
$ vault write transform/encode/my-transform-role value=1111-2222-3333-4444
Key              Value
---              -----
encoded_value    1606-8311-1961-4492

$ vault write transform/encode/my-transform-role value=1111-2222-3333-4444
Key              Value
---              -----
encoded_value    1606-8311-1961-4492


$ vault write transform/decode/my-transform-role value=1606-8311-1961-4492
Key              Value
---              -----
decoded_value    1111-2222-3333-4444
```

暗号化された値は同一の値を返し、複合化可能です。

次にTweak値を生成するモードに変更します。`tweak_source=generated`です。

```shell
$ vault write transform/transformation/first-transform \
type=fpe \
template=builtin/creditcardnumber \
allowed_roles=my-transform-role \
tweak_source=generated
```

この状態で暗号化を実施してみましょう。

```console
$ vault write transform/encode/my-transform-role value=1111-2222-3333-4444
Key              Value
---              -----
encoded_value    2620-2046-9436-7135
tweak            3T+WJ0yG9Q==

$ vault write transform/encode/my-transform-role value=1111-2222-3333-4444
Key              Value
---              -----
encoded_value    5776-7465-2375-4346
tweak            Jv/kQc9YuQ==
```

実行ごとに別々の値が生成され、それぞれにTweak値が生成されていることがわかるでしょう。
このモードの際、正しく値を取り出すに暗号文に合わせてTweak値が必ず必要です。

まずTweak値を入力せずに試してみます。`value`には上の2回目に生成された`encoded_value`を入れてください。

```console
$ vault write transform/decode/my-transform-role value=5776-7465-2375-4346
Error writing data to transform/decode/my-transform-role: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/transform/decode/my-transform-role
Code: 400. Errors:

* incorrect tweak size provided: 0
```

次にTweak値を入れて試してみます。`tweak`には上の2回目に生成された`tweak`を入れてください。

```console
$ vault write transform/decode/my-transform-role value=5776-7465-2375-4346 tweak=Jv/kQc9YuQ==
Key              Value
---              -----
decoded_value    1111-2222-3333-4444
```

正しく復元できました。最後にTweak値に不正確な値を入れてみましょう。`tweak`には上の1回目に生成された`tweak`を入れてください。

```console
$ vault write transform/decode/my-transform-role value=5776-7465-2375-4346 tweak=3T+WJ0yG9Q==
Key              Value
---              -----
8534-4499-6272-2127
```

正しい値が返ってこないはずです。このようにTweakを利用することでより高度にデータの暗号化を行うことが可能です。

## Maskingを試す

最後に`Masking`を試してみましょう。`Masking`は`one-way encryption`と呼んでいますが、その名の通り、マスキングしたデータは複合化することはできません。

文字通り「データを隠すため」の機能です。そのため、オペミスを防ぐため、`FPE`のタイプのものから`Masking`への変更はできないようになっています。`FPE`は複合化が前提となっているユースケースで利用するからです。

`Transformation`を以下のように作成します。

```shell
$ vault write transform/transformations/masking/masking-email \
template=email-template \
allowed_roles=my-transform-role \
tweak_source=internal
```

確認してみましょう。

```console
$ vault read transform/transformation/masking-email
Key                  Value
---                  -----
allowed_roles        [my-transform-role]
masking_character    42
templates            [email-template]
type                 masking
```

```shell
vault write transform/role/my-transform-role \
transformations=first-transform,email,masking-email
```

これを利用してデータをマスキングしてみます。

```console
$ vault write transform/encode/my-transform-role value="email@kabuctl.com" transformation=masking-email
Key              Value
---              -----
encoded_value    *****@*******.***
```

このようにマスキングされた値が返ってきます。

ちなみに、マスキングする文字列は変更できます。`masking_character=#`を追加してみましょう。

```shell
$ vault write transform/transformations/masking/masking-email \
template=email-template \
allowed_roles=my-transform-role \
tweak_source=internal \
masking_character=#
```

再度データをマスキングしてみます。

```console
$ vault write transform/encode/my-transform-role value="email@kabuctl.com" transformation=masking-email
Key              Value
---              -----
encoded_value    #####@#######.###
```

変更が反映されました。

この機能は例えばWebブラウザやATMの画面に実際の値を出したくない際や、ログにPIIのデータを出力させたくない時に利用できます。

正規表現を変更することで一部の値のみマスキングすることも可能です。最後にこれを試してみましょう。

アットマーク前の最初と最後の文字を除いた文字列のみマスキングするような表現をしています。

```shell
$ vault write transform/template/email-template \
type=regex \
pattern='.([0-9A-Za-z]{1,100}).@.*' \
alphabet=localemailaddress
```

```console
$ vault write transform/encode/my-transform-role value="takayukikaburagi@kabuctl.com" transformation=masking-email
Key              Value
---              -----
encoded_value    t##############i@kabuctl.com
```

以上で一通りの`Transform Secret Engine`の機能を試すことができました。`Alphabets`と`Templates`の`Patterne`の正規表現を利用することで様々なデータのTransformationを実現することができます。

また、時間のある方はこちらの[サンプルアプリ](https://github.com/tkaburagi/vault-transformation-demo)で実際のWebアプリから利用することを試してみてください。

## 参考リンク
* [Transform Doc](https://www.vaultproject.io/docs/secrets/transform)
* [Transform API](https://www.vaultproject.io/api-docs/secret/transform)
* [Blog Post](https://www.hashicorp.com/blog/transform-secrets-engine/)
* [Tutorial](https://learn.hashicorp.com/vault/adp/transform)
