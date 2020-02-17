# Policyのエクササイズ

PolicyはVaultにとって非常に大切なものです。
まず、Vaultは全てPathベースになっています。Policyも当然Pathベースになります。

Policyによって、各Pathに対して細かいアクセス制御（**Capabilities**)を設定できます。

Capabilitiesには以下のようなものがあります。

Capabilities  | 内容  |  対応するHTTP API method
--|---|--
create | データの作成を許可  | `POST` `PUT`
read  | データの読み取りを許可  | `GET`
update | データの変更を許可 | `POST` `PUT`
delete | データの削除を許可  | `DELETE`
list  | Pathにあるデータのリストを表示  | `LIST`
sudo  | `root-protected`のPathへのアクセスを許可  | n/a
deny  | 全てのアクセスを禁止  | n/a

上記のうち、**sudo**と**deny**は特殊なCapabilitiesです。特にsudoはVaultの管理APIなどへのアクセスをコントロールするので、主に管理者向けのCapabilitiesとなります。

`root-protected`のPathの一覧は[こちら](https://learn.hashicorp.com/vault/identity-access-management/iam-policies#root-protected-api-endpoints)

---
## エクササイズの事前準備


それでは、実際にPolicyを触ってみましょう。まずは環境を構築します。

### Secret engineのマウント

これからのエクササイズで利用するSecret engineを設定します。

```console
vault secrets enable -path=kv_training kv
```

これで、Vault上の`kv_training`というPathにKVのSecret engineがマウントされました。このEngineを使って、この後のエクササイズを行います。

---
## Ex1. ProducerとConsumer

**シナリオ：**

登場人物  | 役割  | アクセス制限
--|---|--
Producer  | Secretを設定する  | KVへSecretを書き込みたい 。複数のユーザへのユニークなSecretを書き込みたい。
Consumer  | Secretを利用する  | KVからSecretを読み出したい。ただし、Secretの変更や、許可されていないSecretへのアクセスは出来ない。

### Policyの準備

まず、Producer側のPolicyを準備します。Policyは、Vault上のPathに対し、どのようなCapabilitiesを許可するか（または許可しないか）を記述します。

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

このPolicyでは、
- kv_training内のSecretのリストを表示できる
- kv_training/　以下の全てのPathに対して書き込み・読み取り・修正・削除ができる

という制御になります。

それでは次にConsumerのPolicyをconsumer.hclという名前で作成します。

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

このPolicyでは、

- kv_training内のSecretのリストを表示できる
- kv_training以下の`consumer_`で始まるSecretに対してのみ読み取りが出来る

という制御になります。

それではこれらのPolicyをVaultに設定します。Policyの作成は、`vault policy write`コマンドで行います。

```console
$ vault policy write producer producer.hcl
Success! Uploaded policy: producer

$ vault policy write consumer consumer.hcl
Success! Uploaded policy: consumer
```

Successと表示されれば正常にVaultにPolicyが書き込まれました。

この後のエクササイズの為に、ConsumerとProducerそれぞれのためのTokenを作成しておきましょう。Tokenの作成は、`vault token create`コマンドを使います。実際のTokenは`s.esHB5Ggj0JoRxkInQrm9eia6`のようなランダムな文字列ですが、ここではエクササイズを簡単にするために、それぞれ`producer_token`と`consumer_token`と簡単なToken名に設定しています（本番環境などでは決して真似しないで下さい）。


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

VaultがWarningを吐いていますが、気にせず先に進みましょう。

---
### ProducerによるSecret作成

それではProducer Tokenを使って、Secretを書き込みます。まずはProducer Tokenでloginします。

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

この状態で、kv_training以下のSecretを表示してみましょう。

```console
$ vault list kv_training
No value found at kv_training/
```

もちろんまだ何も入っていません。それではいくつかのSecretを書き込んでみましょう。以下のコマンドを順に実行してください。

```shell
vault write kv_training/consumer_username key=consumer
vault write kv_training/consumer_password key=P@ssword
vault write kv_training/trainer_username key=trainer
vault write kv_training/trainer_password key=S3CR3T
```

これで、`consumer_`で始まるものと`trainer_`で始まる、4つのSecretが書き込まれました。

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

これでProducerの仕事は終わりです。

---
### ConsumerによるSecretの読み出し

次にConsumerになりきって、先程Producerが作成した自分専用のSecretを読み出せるか試してみます。まずConsumer Tokenを使って、Consumerとしてログインします。

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

この状態で`kv_secret`内のSecretを表示してみましょう。

```console
$ vault list kv_training
Keys
----
consumer_password
consumer_username
trainer_password
trainer_username
```

Consumer Policyでは、kv_training内のSecretのリスト表示は許可されているので、どのようなSecretがあるかは表示できました。

では、自分用のSecretを読み出して見ましょう。

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

このように、`consumer_`で始まる自分用のSecretは読み出せました。次に`trainer`のSecretを読み出してみましょう。

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

Policyによって制限されているため読み出しはErrorになります。また、Producerの用にSecretを書き込もうとしてもErrorになるはずです。

```console
$ vault write kv_training/consumer_password key=NEWP@ssword
Error writing data to kv_training/consumer_password: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/kv_training/consumer_password
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

時間があれば、PolicyやSecretに変更を加えて色々試してみて下さい。

これで、このエクササイズは終わりです。

---
## Ex2. より細かいPolicyによる制御

ここではPolicyによる、より細かい制御をやってみます。具体的には、以下のような制御を追加します。

- Secretに必須のパラメータを設定する
- SecretのKeyのパラメータに入れても良い値を指定する
- SecretのKeyのパラメータに入れてはいけない値を指定する

それでは一つづつやっていきましょう。

---
### Secretに必須のパラメータを設定する

**前のエクササイズでConsumer tokenでログインしている場合は、rootもしくはPolicyを変更できる権限のTokenでログインし直して下さい。**

まず新たにPolicyを作ります。
このPolicyでは、`required_parameters`で必須のパラメータを指定しています。この例では、このSecretには`username`と`password`という2つのパラメータがないとErrorにする設定になります。

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

つぎにこのPolicyをVaultに設定して、Tokenを作成し、そのTokenでログインします（以下の実行ログでは、これら3つを順番に行なっています)。

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

ここであえて、必須パラメータを1つ足りないSecretを書き込んでみます。

```console
$ vault write kv_training/new_secret username="foo"
Error writing data to kv_training/new_secret: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/kv_training/new_secret
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```

予想通りErrorになりました。では、Policyで指定されている2つのパラメータで書き込んでみます。

```console
$ vault write kv_training/new_secret username="foo" password="bar"
Success! Data written to: kv_training/new_secret
```

予想通り成功しました。

> **注意：　上記の通りwriteについては想定どおりの挙動をしますが、現時点（Vault 1.3）ではReadについてもPolicyの制限が継承されてしまいReadができないというBugがあります。**

---
### SecretのKeyのパラメータに入れても良い値を指定する

WIP

---
### SecretのKeyのパラメータに入れてはいけない値を指定する

WIP
