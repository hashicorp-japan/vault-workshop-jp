Table of Contents
=================

   * [Table of Contents](#table-of-contents)
   * [Transit シークレットエンジンで Vault を Encryption as a Sevice として使う](#transitシークレットエンジンでvaultをencryption-as-a-seviceとして使う)
      * [Transit を有効化する。](#transitを有効化する)
      * [初めての暗号化と復号化](#初めての暗号化と復号化)
         * [キーローテーション](#キーローテーション)
      * [Convergent 暗号化を試す](#convergent暗号化を試す)
      * [実際のアプリで使ってみる](#実際のアプリで使ってみる)
      * [参考リンク](#参考リンク)

# Transit シークレットエンジンで Vault を Encryption as a Sevice として使う

これまで Vault のシークレット管理の機能を扱ってきましたが、Vault の二つ目のユースケースは`Data Protection`です。その中でも API ドリブンな Encryption の機能を使って Vault を暗号化としてのサービスとして扱う`Encryption as a Service (EaaS)`は非常に多く採用されているユースケースです。

ここではそれを実現する Transit の機能と、実際のアプリを使った利用イメージを扱います。

## Transit を有効化する。

その他のシークレットエンジンと同様、EaaS を利用する際は`Transit`というシークレットエンジンを`enabled`にします。

```console
$ vault secrets enable -path=transit transit
Success! Enabled the transit secrets engine at: transit/

$ vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_e3aa0798    per-token private secret storage
database/     database     database_603dc42e     n/a
identity/     identity     identity_86c0240d     identity store
kv/           kv           kv_20084de2           n/a
sys/          system       system_ae51ee57       system endpoints used for control, policy and debugging
transit/      transit      transit_ec14846c      n/a
```

Transit が有効になりました。Transit には大きく

* 暗号化
* 復号化
* キーローテーション

の機能があります。

## 初めての暗号化と復号化

早速データを暗号化してみましょう。Transit で暗号化するためには Plaintext は base64 で暗号化する必要があります。macOS であればターミナルから実行可能ですし、[こちら](https://kujirahand.com/web-tools/Base64.php)の Web サイトでもエンコードができます。

`myimportantpassword`というパスワードを暗号化してみます。

```console
$ base64 <<< "myimportantpassword"
bXlpbXBvcnRhbnRwYXNzd29yZAo=
```

これを`transit/encrypt/`のエンドポイントを使って暗号化キーを作り、暗号化します。`my-encrypt-key`は暗号化キーの名前です。

```console
$ vault write transit/encrypt/my-encrypt-key plaintext=bXlpbXBvcnRhbnRwYXNzd29yZAo=
Key           Value
---           -----
ciphertext    vault:v1:WputNlwLdegpFARr+OL8Az/UmDRCWsVL3ytVf/AUc9tFHt4YD1NOnfd4iSocUfG5
```

```shell
$ export CTEXT_V1=vault:v1:WputNlwLdegpFARr+OL8Az/UmDRCWsVL3ytVf/AUc9tFHt4YD1NOnfd4iSocUfG5
```
この暗号化の機能は base64 にさえ変換してしまえば画像など様々な形式のデータを暗号化することができます。

次に復号化をしてみます。復号化は`transit/decrypt/`のエンドポイントを使います。

```console
$ vault write transit/decrypt/my-encrypt-key ciphertext=$CTEXT_V1
Key          Value
---          -----
---          -----
plaintext    bXlpbXBvcnRhbnRwYXNzd29yZAo=
```

`plaintext`として Base64 のコードが表示されました。これをデコードしてパスワードを取り出してみます。

```console
$ base64 --decode <<< "bXlpbXBvcnRhbnRwYXNzd29yZAo="
myimportantpassword
```

無事に復号化できました。

暗号化キーは様々なアルゴリズムをサポートしており、`type`で指定可能です。

* aes256-gcm96 (Default)
* chacha20-poly1305 
* ed25519 
* ecdsa-p256 
* rsa-2048 
* rsa-4096

### キーローテーション

暗号化、復号化のキーはどれだけ強力なアルゴリズムを使っても時間をかければ必ず解読出来てしまいます。そのため環境を最大限にセキュアに保つためにはキー自体をローテーションさせ、長く使わず短いサイクルでリニューアルすることが大切です。

Transit では`transit/keys/<KEYNAME>/rotate`と`transit/rewrap/<KEYNMAME>`というエンドポイントで簡単に実現できます。

`rotate`はキーの更新、`rewarp`は古いデータを新しいキーで再暗号化するためのエンドポイントです。

```console
$ vault write -f transit/keys/my-encrypt-key/rotate
$ vault read transit/keys/my-encrypt-key
Key                       Value
---                       -----
allow_plaintext_backup    false
deletion_allowed          false
derived                   false
exportable                false
keys                      map[2:1563181079 1:1563181077]
latest_version            2
min_available_version     0
min_decryption_version    1
min_encryption_version    0
name                      my-encrypt-key
supports_decryption       true
supports_derivation       true
supports_encryption       true
supports_signing          false
type                      aes256-gcm96
```

バージョンが 2 に変わりました。`min_decryption_version`はこのデータが復号化できる最小のキーのバージョンを示しています。まずはこの状態で新しいデータを暗号化してみましょう。

```console
$ base64 <<< "myimportantpassword-v2"
bXlpbXBvcnRhbnRwYXNzd29yZC12Mgo=

$ vault write transit/encrypt/my-encrypt-key plaintext=bXlpbXBvcnRhbnRwYXNzd29yZC12Mgo=

Key           Value
---           -----
ciphertext    vault:v2:93WEsl7Q7UM/eWHGZP+N9PmOEqXPYpnpVeBx21APu7pT1MOCJElJ7AkbiNgdr0gVOALw
```

```shell
$ export CTEXT_V2=vault:v2:93WEsl7Q7UM/eWHGZP+N9PmOEqXPYpnpVeBx21APu7pT1MOCJElJ7AkbiNgdr0gVOALw
```

新しいデータは v2 のキーで暗号化復号化され、それ以前のデータは古いキーで復号化されます。v1 と v2 で暗号化したデータをそれぞれ復号化してみます。

```console
$ vault write transit/decrypt/my-encrypt-key ciphertext=$CTEXT_V1

Key          Value
---          -----
plaintext    bXlpbXBvcnRhbnRwYXNzd29yZAo=

$ vault write transit/decrypt/my-encrypt-key ciphertext=$CTEXT_V2

Key          Value
---          -----
plaintext    bXlpbXBvcnRhbnRwYXNzd29yZC12Mgo=
```

V1, V2 のデータ共に複合化可能です。この状態でいずれ v2 の新しいキーに全てのデータを移行したいです。そのためには`rewrap`という操作を行い、古いデータの更新(再暗号化)を行います。`ciphertext`には v1 のデータを入れてください。

```console
$ vault write transit/rewrap/my-encrypt-key ciphertext=$CTEXT_V1

Key           Value
---           -----
ciphertext    vault:v2:pymUK9PJQ3KYXSw7uNj/lcTMOwfNav2t3pP52jAuQWQ6bTHNd9n/3tX4Zdc/IPLt
```
これで v1 で暗号化したデータを v2 で暗号化しました。次に、`min_decryption_version`を更新し v1 のキーを無効化し、利用できないようにします。

```shell
export CTEXT_V1_V2=vault:v2:pymUK9PJQ3KYXSw7uNj/lcTMOwfNav2t3pP52jAuQWQ6bTHNd9n/3tX4Zdc/IPLt
```

```console
$ vault write  transit/keys/my-encrypt-key/config min_decryption_version=2

Success! Data written to: transit/keys/my-encrypt-key/config

$ vault write transit/decrypt/my-encrypt-key ciphertext=$CTEXT_V1_V2

Key          Value
---          -----
plaintext    bXlpbXBvcnRhbnRwYXNzd29yZAo=

$ vault write transit/decrypt/my-encrypt-key ciphertext=$CTEXT_V1
Error writing data to transit/decrypt/my-encrypt-key: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/transit/decrypt/my-encrypt-key
Code: 400. Errors:

* ciphertext or signature version is disallowed by policy (too old)
```

v1 のデータは復号化出来なくなり、v1 のキーが無効になっていることがわかります。

## Convergent 暗号化を試す

次に Convergent(収束)暗号化を試してみます。Convergent は一般的な暗号化の手法で、特定のキーを利用し同一のプレインテキストで暗号化されたものは毎回同一の暗号文を返すというものです。

Vault の暗号化はデフォルトでは同じ平文であっても毎回別の暗号文が生成されます。ところが暗号化したいが重複データを避けたい場合や暗号データを検索したいような場合、同じ平文は同じ暗号文で返して欲しい際があります。

Vault では暗号化キーを生成する際にこの Convergent 暗号化のパラメータを指定することで実現可能です。

まずは新しいキーを生成してみましょう。

```shell
$ vault write transit/keys/convergent-key type="chacha20-poly1305" convergent_encryption=true derived=true
```

Convergent に対応しているタイプのアルゴリズムを指定しています。この他にもあるので[こちら](https://www.vaultproject.io/api/secret/transit/index.html#type)で確認してみてください。

```console
$ vault read transit/keys/convergent-key
Key                              Value
---                              -----
allow_plaintext_backup           false
convergent_encryption            true
convergent_encryption_version    -1
deletion_allowed                 false
derived                          true
exportable                       false
kdf                              hkdf_sha256
keys                             map[1:1579319629]
latest_version                   1
min_available_version            0
min_decryption_version           1
min_encryption_version           0
name                             convergent-key
supports_decryption              true
supports_derivation              true
supports_encryption              true
supports_signing                 false
type                             chacha20-poly1305
```

Convernt が true になっているキーが生成したことがわかります。`derived`は`Key Derivation Function`を有効化するためのパラメータで Vault では Convergent を有効化する際に必須となります。

これによってクライアントが同一の暗号文を保持したとしても`context`パラメータを指定しないと復号化が不可能となり、より安全にデータを扱うことができます。

```console
$ vault write transit/encrypt/convergent-key plaintext=$(base64 <<< "myimportantpassword") context=$(base64 <<< "c2FtcGxxxx9udGV4dA")

Key           Value
---           -----
ciphertext    vault:v1:NuH3WBB956hNZOnPYZqo5lb86bZ5LN1BTKlmuZ78ZGzB2HYdcl9iAbh5hdxCC/1k
```

`Value`で出力される暗号文をコピーし、復号化してみましょう。

```console
$ base64 --decode <<< $(vault write -format=json transit/decrypt/convergent-key ciphertext="vault:v1:NuH3WBB956hNZOnPYZqo5lb86bZ5LN1BTKlmuZ78ZGzB2HYdcl9iAbh5hdxCC/1k" context=$(base64 <<< "c2FtcGxxxx9udGV4dA") | jq -r '.data.plaintext')

myimportantpassword
```

復号化出来ました。試しに`context`に別の値を入れてみましょう。

```console
$ base64 --decode <<< $(vault write -format=json transit/decrypt/convergent-key ciphertext="vault:v1:NuH3WBB956hNZOnPYZqo5lb86bZ5LN1BTKlmuZ78ZGzB2HYdcl9iAbh5hdxCC/1k" context=$(base64 <<< "samplecontext") | jq -r '.data.plaintext')

Error writing data to transit/decrypt/convergent-key: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/transit/decrypt/convergent-key
Code: 400. Errors:

* invalid ciphertext: unable to decrypt
```

エラーになり、復号化出来ないはずです。このようにキーへのアクセス権や暗号化文を保持していても`context`を持っていないと復号化することが出来ず、データを守ることが出来ます。

最後に試しに Convergent が設定されているか再度同じ平文を暗号化してみます。

```console
$ vault write transit/encrypt/convergent-key plaintext=$(base64 <<< "myimportantpassword") context=$(base64 <<< "c2FtcGxxxx9udGV4dA")

Key           Value
---           -----
ciphertext    vault:v1:NuH3WBB956hNZOnPYZqo5lb86bZ5LN1BTKlmuZ78ZGzB2HYdcl9iAbh5hdxCC/1k
```

先ほどと同じ暗号文が返されるはずです。

余裕のある方は以下の内容を前の手順を振り返りながら試してみてください。

* `convergent-key`で別の平文を使って暗号化
* `convergent-key`を`rotate`して同じ平文`myimportantpassword`を暗号化
* 別の Convergent を生成して同じ平文`myimportantpassword`を暗号化

## 実際のアプリで使ってみる

次に利用イメージをもう少し理解しやすくするため、Spring のアプリで Transit を利用してみます。アプリのレポジトリを clone し起動します。

まずデータベースにテーブルを作ります。MySQL にログインし、以下のコマンドを発行します。

この手順を完了するには[Java 12](https://www.oracle.com/technetwork/java/javase/downloads/jdk12-downloads-5295953.html)が必要です。

```mysql
use handson;
create table users (id varchar(50), username varchar(50), password varchar(200), email varchar(50), address varchar(50), creditcard varchar(200));
```

次にロールの設定をします。ロールは二つ作成します。

* MySQL データベースとやりとりしてデータの select, insert をするための`database/*`配下のロール
* Vault とやりとりして Transit で暗号化復号化をするための`auth/*`配下のロール

まずはデータベース側です。コンフィグをアップデートし、`role-demoapp`というロールを許可します。

```shell
$ vault write database/config/mysql-handson-db \
  plugin_name=mysql-legacy-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="role-handson","role-handson-2","role-handson-3","role-demoapp" \
  username="root" \
  password="rooooot"
```

ロールを作成します。`handson.users`のテーブルに対して`SELECT`, `INSERT`の権限のあるロールです。

```shell
$ vault write database/roles/role-demoapp \
  db_name=mysql-handson-db \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT,INSERT,UPDATE ON handson.users TO '{{name}}'@'%';" \
  default_ttl="5h" \
  max_ttl="5h"
```

動作を確認しておきましょう。ここで生成したユーザ名パスワードは利用せず、実際にこの操作はアプリから実施することになります。

```console
$ vault read database/creds/role-demoapp

Key                Value
---                -----
lease_id           database/creds/role-demoapp/GwOQKPDCIJS1K1Z626RdrQlW
lease_duration     5h
lease_renewable    true
password           A1a-4VU2FVBp5HdIJGvz
username           v-role-FWRN0zpOp
```

次に Vault 認証用のロールです。ここで作るポリシーは`AppRole`の認証で付与されるトークンの権限となります。以下のようにポリシーの定義ファイルを作成してください。

```hcl
$ cat > policy-vault.hcl <<EOF
# Enable transit secrets engine
path "sys/mounts/transit" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# To read enabled secrets engines
path "sys/mounts" {
  capabilities = [ "read" ]
}

# Manage the transit secrets engine
path "transit/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}
EOF
```

AppRole が有効になっていない方は下記のコマンドで有効化しましょう。
```shell
$ vault auth enable approle
```

```console
$ vault policy write vault-policy policy-vault.hcl
$ vault write auth/approle/role/vault-approle policies=vault-policy period=1h
```

これで準備は完了です。アプリをクローンして、起動してみましょう。`YOUR_ROOT_TOKEN`はご自身の Root Token です。

```console
$ export ROOT_TOKEN=<YOUR_ROOT_TOKEN>
$ git clone https://github.com/tkaburagi/spring-vault-transit-demo
$ cd spring-vault-transit-demo
$ sed "s|VAULT_TOKEN=|VAULT_TOKEN=$ROOT_TOKEN|g" set-env-local.sh > my-set-env-local.sh
$ cat my-set-env-local.sh
$ source my-set-env-local.sh
$ ./mvnw clean package -DskipTests
$ java -jar target/demo-0.0.1-SNAPSHOT.jar
  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
 :: Spring Boot ::        (v2.1.4.RELEASE)

2019-07-15 21:50:19.739  INFO 7226 --- [           main] com.example.demo.VaultDemoApplication    : Starting VaultDemoApplication v0.0.1-SNAPSHOT on Takayukis-MacBook-Pro.local with PID 7226 (/Users/kabu/hashicorp/intellij/springboot-vault-transit/target/demo-0.0.1-SNAPSHOT.jar started by kabu in /Users/kabu/hashicorp/intellij/springboot-vault-transit)
2019-07-15 21:50:19.741  INFO 7226 --- [           main] com.example.demo.VaultDemoApplication    : No active profile set, falling back to default profiles: default
```

コードの説明は後ほどしますが、このアプリには 4 つのエンドポイントがあります。

まずはパラメータで渡された文字列を暗号化、復号化する単純なエンドポイントです。

```console
$ curl -G http://localhost:8080/api/v1/transit/encrypt -d "ptext=hellotransit" 
vault:v1:Wa87EPlyIe0xaF8R+725/j8XRB18cbM8PfGLjM0jmlRCaVD0FmGJQg==

$ curl -G http://localhost:8080/api/v1/transit/decrypt --data-urlencode "ctext=vault:v1:9ZNILrEWKswi+lHhzGRXHfN0sY+idGEIHQZ4IVeLRNey/pNLibKZ6Q=="
hellotransit                            
```

次にデータを暗号化し、データベースにデータを保存するエンドポイントです。`api/v1/encrypt/add-user`に平文でデータを渡すと暗号化され、データベースに暗号刺されたデータが insert されます。

```console
$ curl http://localhost:8080/api/v1/encrypt/add-user -d username="Takayuki Kaburagi" -d password="PqssWOrd" -d address="Yokohama" --data-urlencode creditcard="9999-8888-6666-6666" --data-urlencode email="t.kaburagi@me.com"

{"id":"db0bbb62-fdfd-4e2e-a4db-1e5e32e36761","username":"Takayuki Kaburagi","password":"vault:v1:aRtAJK+ED8ap2vM5f9ba8eL0VvnjD+Akw8ag2eHLYNucXfRx","email":"h.kaburagi@me.com","address":"Yokohama","creditcard":"vault:v1:LYpkecFI4bY6c7I8a3fB47d0oHNf6bPL/6VTc14g+zgEVg47EoRjKWTJeYeaisw="}
```

データベースで確認してみましょう。

```mysql
mysql> select * from users;
+--------------------------------------+-----------------+-----------------------------------------------------------+-------------------+----------+---------------------------------------------------------------------------+
| id                                   | username        | password                                                  | email             | address  | creditcard                                                                |
+--------------------------------------+-----------------+-----------------------------------------------------------+-------------------+----------+---------------------------------------------------------------------------+
| db0bbb62-fdfd-4e2e-a4db-1e5e32e36761 | Takayuki Kaburagi | vault:v1:aRtAJK+ED8ap2vM5f9ba8eL0VvnjD+Akw8ag2eHLYNucXfRx | t.kaburagi@me.com | Yokohama | vault:v1:LYpkecFI4bY6c7I8a3fB47d0oHNf6bPL/6VTc14g+zgEVg47EoRjKWTJeYeaisw= |
+--------------------------------------+-----------------+-----------------------------------------------------------+-------------------+----------+---------------------------------------------------------------------------+
```

暗号されたデータが保存されていることがわかります。次にデータを取り出すためのエンドポイントです。`api/v1/plain/get-use`ではデータをそのまま取り出します。上の`uuid`の値をメモしてください。

```console
$ curl -G "http://localhost:8080/api/v1/non-decrypt/get-user" -d uuid=d87b7a21-0a33-4e64-a05d-60065eed71a9 | jq

{
  "id": "db0bbb62-fdfd-4e2e-a4db-1e5e32e36761",
  "username": "Hiroki Kaburagi",
  "password": "vault:v1:aRtAJK+ED8ap2vM5f9ba8eL0VvnjD+Akw8ag2eHLYNucXfRx",
  "email": "h.kaburagi@me.com",
  "address": "Yokohama",
  "creditcard": "vault:v1:LYpkecFI4bY6c7I8a3fB47d0oHNf6bPL/6VTc14g+zgEVg47EoRjKWTJeYeaisw="
```

この場合、データは暗号化されたままなのでアプリ側で復号の処理を実装する必要があります。Vault の場合、それを Vault に委託することが可能です。`api/v1/decrypt/get-user`を使います。

```console
$ curl -G "http://localhost:8080/api/v1/decrypt/get-user" -d uuid=db0bbb62-fdfd-4e2e-a4db-1e5e32e36761 | jq

{
  "id": "db0bbb62-fdfd-4e2e-a4db-1e5e32e36761",
  "username": "Takayuki Kaburagi",
  "password": "PqssWOrd",
  "email": "t.kaburagi@me.com",
  "address": "Yokohama",
  "creditcard": "9999-8888-6666-6666"
  ```

Vault に復号化し、アプリのデータとして利用することが出来るようになりました。このように Vault ではシークレット管理だけでなく暗号化の処理をサービスとして扱えるようにするような使い方をすることができます。


最後にキーのローテーションと Rewrap をしてみます。`get-keys`のエンドポイントでアプリからキーの情報が取り出せるようになっています。

```console
$ curl -G http://localhost:8080/api/v1/get-keys | jq

{
  "name": [
    "springdemo"
  ],
  "type": "aes256-gcm96",
  "latest_version": 1,
  "min_decrypt_version": 1
}
```

まずキーをローテーションします。

```console
$ vault write -f transit/keys/springdemo/rotate
$ curl -G http://localhost:8080/api/v1/get-keys | jq

{
  "name": [
    "springdemo"
  ],
  "type": "aes256-gcm96",
  "latest_version": 2,
  "min_decrypt_version": 1
}
```

新しいデータを投入してみましょう。

```shell
curl http://localhost:8080/api/v1/encrypt/add-user -d username="Yusuke Kaburagi" -d password="PqssWOrd" -d address="Tokyo" --data-urlencode creditcard="9999-8888-6666-6666" --data-urlencode email="yusuke@locahost"
```

v1, v2 のデータが両方入っていることがわかります。

```shell
mysql> select * from users;
```

v1 のデータを v2 に Rewrap してみます。このアプリでは`api/v1/rewrap`のエンドポイントで実現しています。

```shell
curl -G http://localhost:8080/api/v1/rewrap -d uuid=<OLD DATA'S UUID> | jq
```

データを見ると v2 に更新されているでしょう。

```shell
mysql> select * from users;
```

あとは同様に`min_decryption_version`を bump すれば完了です。

```shell
$ vault write  transit/keys/springdemo/config min_decryption_version=2
$ curl -G http://localhost:8080/api/v1/get-keys | jq

{
  "name": [
    "springdemo"
  ],
  "type": "aes256-gcm96",
  "latest_version": 2,
  "min_decrypt_version": 2
```

## 参考リンク
* [Transit](https://www.vaultproject.io/docs/secrets/transit/index.html)
* [API Document](https://www.vaultproject.io/api/secret/transit/index.html)
* [Spring Cloud Vault](https://cloud.spring.io/spring-cloud-vault/)
* [Spring Vault](https://projects.spring.io/spring-vault/)
