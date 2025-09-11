# Policy のエクササイズ

Policy は Vault にとって非常に大切なものです。
まず、Vault は全て Path ベースになっています。Policy も当然 Path ベースになります。

Policy によって、各 Path に対して細かいアクセス制御（**Capabilities**)を設定できます。

Capabilities には以下のようなものがあります。

Capabilities  | 内容  |  対応する HTTP API method
--|---|--
create | データの作成を許可  | `POST` `PUT`
read  | データの読み取りを許可  | `GET`
update | データの変更を許可 | `POST` `PUT`
delete | データの削除を許可  | `DELETE`
list  | Path にあるデータのリストを表示  | `LIST`
sudo  | `root-protected`の Path へのアクセスを許可  | n/a
deny  | 全てのアクセスを禁止  | n/a

上記のうち、**sudo**と**deny**は特殊な Capabilities です。特に sudo は Vault の管理 API などへのアクセスをコントロールするので、主に管理者向けの Capabilities となります。

`root-protected`の Path の一覧は[こちら](https://learn.hashicorp.com/vault/identity-access-management/iam-policies#root-protected-api-endpoints)

---
## エクササイズの事前準備


それでは、実際に Policy を触ってみましょう。まずは環境を構築します。

### Secret engine のマウント

これからのエクササイズで利用する Secret engine を設定します。

```console
vault secrets enable -path=kv_training kv
```

これで、Vault 上の`kv_training`という Path に KV の Secret engine がマウントされました。この Engine を使って、この後のエクササイズを行います。

---
## Ex1. Producer と Consumer

**シナリオ：**

登場人物  | 役割  | アクセス制限
--|---|--
Producer  | Secret を設定する  | KV へ Secret を書き込みたい 。複数のユーザへのユニークな Secret を書き込みたい。
Consumer  | Secret を利用する  | KV から Secret を読み出したい。ただし、Secret の変更や、許可されていない Secret へのアクセスは出来ない。

### Policy の準備

まず、Producer 側の Policy を準備します。Policy は、Vault 上の Path に対し、どのような Capabilities を許可するか（または許可しないか）を記述します。

以下のようなファイルを作成し、`producer.hcl`として保存して下さい。

```hcl
$ cat <<EOF> producer.hcl

path "kv_training"
{
	capabilities = [ "list" ]
}

path "kv_training/*"
{
	capabilities = [ "create", "read", "update", "delete", "list" ]
}
EOF
```

この Policy では、
- kv_training 内の Secret のリストを表示できる
- kv_training/　以下の全ての Path に対して書き込み・読み取り・修正・削除ができる

という制御になります。

それでは次に Consumer の Policy を consumer.hcl という名前で作成します。

```hcl
$ cat <<EOF> consumer.hcl
path "kv_training"
{
	capabilities = [ "list" ]
}

path "kv_training/consumer_*"
{
	capabilities = [ "read" ]
}
EOF
```

この Policy では、

- kv_training 内の Secret のリストを表示できる
- kv_training 以下の`consumer_`で始まる Secret に対してのみ読み取りが出来る

という制御になります。

それではこれらの Policy を Vault に設定します。Policy の作成は、`vault policy write`コマンドで行います。

```console
$ vault policy write producer producer.hcl
Success! Uploaded policy: producer

$ vault policy write consumer consumer.hcl
Success! Uploaded policy: consumer
```

Success と表示されれば正常に Vault に Policy が書き込まれました。

この後のエクササイズの為に、Consumer と Producer それぞれのための Token を作成しておきましょう。Token の作成は、`vault token create`コマンドを使います。実際の Token は`s.esHB5Ggj0JoRxkInQrm9eia6`のようなランダムな文字列ですが、ここではエクササイズを簡単にするために、それぞれ`producer_token`と`consumer_token`と簡単な Token 名に設定しています（本番環境などでは決して真似しないで下さい）。


```console
$ vault token create -policy=producer -id producer_token
WARNING! The following warnings were returned from Vault:

  * Supplying a custom ID for the token uses the weaker SHA1 hashing instead
  of the more secure SHA2-256 HMAC for token obfuscation. SHA1 hashed tokens
  on the wire leads to less secure lookups.

Key                  Value
---                  -----
token                producer_token
token_accessor       ej7jPSlmXYBOkpILCQ42j3Kk
token_duration       768h
token_renewable      true
token_policies       ["default" "producer"]
identity_policies    []
policies             ["default" "producer"]

$ vault token create -policy=consumer -id consumer_token
WARNING! The following warnings were returned from Vault:

  * Supplying a custom ID for the token uses the weaker SHA1 hashing instead
  of the more secure SHA2-256 HMAC for token obfuscation. SHA1 hashed tokens
  on the wire leads to less secure lookups.

Key                  Value
---                  -----
token                consumer_token
token_accessor       QZdNTXBir9JjcQHJySlCm2Q7
token_duration       768h
token_renewable      true
token_policies       ["consumer" "default"]
identity_policies    []
policies             ["consumer" "default"]
```

Vault が Warning を吐いていますが、気にせず先に進みましょう。

---
### Producer による Secret 作成

それでは Producer Token を使って、Secret を書き込みます。まずは Producer Token で login します。

```console
$ vault login producer_token
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                producer_token
token_accessor       ej7jPSlmXYBOkpILCQ42j3Kk
token_duration       767h53m20s
token_renewable      true
token_policies       ["default" "producer"]
identity_policies    []
policies             ["default" "producer"]
```

この状態で、kv_training 以下の Secret を表示してみましょう。

```console
$ vault list kv_training
No value found at kv_training/
```

もちろんまだ何も入っていません。それではいくつかの Secret を書き込んでみましょう。以下のコマンドを順に実行してください。

```shell
vault write kv_training/consumer_username key=consumer
vault write kv_training/consumer_password key=P@ssword
vault write kv_training/trainer_username key=trainer
vault write kv_training/trainer_password key=S3CR3T
```

これで、`consumer_`で始まるものと`trainer_`で始まる、4 つの Secret が書き込まれました。

念の為、ちゃんと書き込まれたかチェック知てみましょう。

```console
$ vault list kv_training
Keys
----
consumer_password
consumer_username
trainer_password
trainer_username
```

これで Producer の仕事は終わりです。

---
### Consumer による Secret の読み出し

次に Consumer になりきって、先程 Producer が作成した自分専用の Secret を読み出せるか試してみます。まず Consumer Token を使って、Consumer としてログインします。

```console
$ vault login consumer_token
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                consumer_token
token_accessor       QZdNTXBir9JjcQHJySlCm2Q7
token_duration       767h40m28s
token_renewable      true
token_policies       ["consumer" "default"]
identity_policies    []
policies             ["consumer" "default"]
```

この状態で`kv_secret`内の Secret を表示してみましょう。

```console
$ vault list kv_training
Keys
----
consumer_password
consumer_username
trainer_password
trainer_username
```

Consumer Policy では、kv_training 内の Secret のリスト表示は許可されているので、どのような Secret があるかは表示できました。

では、自分用の Secret を読み出して見ましょう。

```console
$ vault read kv_training/consumer_password
Key                 Value
---                 -----
refresh_interval    768h
key                 P@ssword

$ vault read kv_training/consumer_username
Key                 Value
---                 -----
refresh_interval    768h
key                 consumer
```

このように、`consumer_`で始まる自分用の Secret は読み出せました。次に`trainer`の Secret を読み出してみましょう。

```console
$ vault read kv_training/trainer_password
Error reading kv_training/trainer_password: Error making API request.

URL: GET http://127.0.0.1:8200/v1/kv_training/trainer_password
Code: 403. Errors:

* 1 error occurred:
	* permission denied


$ vault read kv_training/trainer_username
Error reading kv_training/trainer_username: Error making API request.

URL: GET http://127.0.0.1:8200/v1/kv_training/trainer_username
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

Policy によって制限されているため読み出しは Error になります。また、Producer の用に Secret を書き込もうとしても Error になるはずです。

```console
$ vault write kv_training/consumer_password key=NEWP@ssword
Error writing data to kv_training/consumer_password: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/kv_training/consumer_password
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

時間があれば、Policy や Secret に変更を加えて色々試してみて下さい。

これで、このエクササイズは終わりです。

---
## Ex2. より細かい Policy による制御

ここでは Policy による、より細かい制御をやってみます。具体的には、以下のような制御を追加します。

- Secret に必須のパラメータを設定する
- Secret の Key のパラメータに入れても良い値を指定する
- Secret の Key のパラメータに入れてはいけない値を指定する

それでは一つづつやっていきましょう。

---
### Secret に必須のパラメータを設定する

**前のエクササイズで Consumer token でログインしている場合は、root もしくは Policy を変更できる権限の Token でログインし直して下さい。**

まず新たに Policy を作ります。
この Policy では、`required_parameters`で必須のパラメータを指定しています。この例では、この Secret には`username`と`password`という 2 つのパラメータがないと Error にする設定になります。

```console
# Policyの作成

$ cat <<EOF>> producer2.hcl

path "kv_training"
{
    capabilities = [ "list" ]
}    

path "kv_training/*"
{
    capabilities = [ "create", "read", "update", "delete", "list" ]
    required_parameters = [ "username", "password" ]
}
EOF
```

つぎにこの Policy を Vault に設定して、Token を作成し、その Token でログインします（以下の実行ログでは、これら 3 つを順番に行なっています)。

```
# Policyの登録

$ vault policy write producer2 producer2.hcl
Success! Uploaded policy: producer2

# Tokenの作成

$ vault token create -policy=producer2 -id=producer2_token
WARNING! The following warnings were returned from Vault:

  * Supplying a custom ID for the token uses the weaker SHA1 hashing instead
  of the more secure SHA2-256 HMAC for token obfuscation. SHA1 hashed tokens
  on the wire leads to less secure lookups.

Key                  Value
---                  -----
token                producer2_token
token_accessor       qF6HtnPM27VI4vAyU2mPMCBp
token_duration       768h
token_renewable      true
token_policies       ["default" "producer2"]
identity_policies    []
policies             ["default" "producer2"]

# 作成したTokenでログイン

$ vault login producer2_token
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                producer2_token
token_accessor       qF6HtnPM27VI4vAyU2mPMCBp
token_duration       767h56m53s
token_renewable      true
token_policies       ["default" "producer2"]
identity_policies    []
policies             ["default" "producer2"]

```

ここであえて、必須パラメータを 1 つ足りない Secret を書き込んでみます。

```console
$ vault write kv_training/new_secret username="foo"
Error writing data to kv_training/new_secret: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/kv_training/new_secret
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

予想通り Error になりました。では、Policy で指定されている 2 つのパラメータで書き込んでみます。

```console
$ vault write kv_training/new_secret username="foo" password="bar"
Success! Data written to: kv_training/new_secret
```

予想通り成功しました。

> **注意：　上記の通り write については想定どおりの挙動をしますが、現時点（Vault 1.3）では Read についても Policy の制限が継承されてしまい Read ができないという Bug があります。**

---
### Secret の Key のパラメータに入れても良い値を指定する

WIP

---
### Secret の Key のパラメータに入れてはいけない値を指定する

WIP
