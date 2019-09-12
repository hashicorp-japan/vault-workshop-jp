# Secret Engine: Databases

ここではデータベースのシークレットエンジンを扱い、MySQLデータベースのシークレットを生成してみます。データベースのシークレットエンジンでは、特定の権限を与えたデータベースユーザを動的に生成、削除することが出来ます。

これにより、複数のクライアントが同じシークレットを使いまわすことを防いだり、たとえシークレットが漏れても即座に破棄するなどの運用が可能になります。

Vaultはデフォルトでは以下のようなDatabaseに対応しています。
* Cassandra
* Influxdb
* HanaDB
* MongoDB
* MSSQL
* MySQL/MariaDB
* PostgreSQL
* Oracle

## Databaseシークレットエンジンの有効化

KVと同様`database`シークレットエンジンを`enable`します。

```console
$ export VAULT_ADDR="http://127.0.0.1:8200"
$ vault secrets enable -path=database database
Success! Enabled the database secrets engine at: database/
```
マウントされた`database/`のエンドポイントを使うことでデータベースシークレットエンジンに対する様々な操作が可能です。

## Databaseの動的シークレットの発行

流れとしては以下の通りです。
* Vaultに特権ユーザのクレデンシャルとデータベースの接続先を登録する
* ロールを定義し、Vaultが発行するデータベースユーザの設定を行う
	* データベースに対する権限
	* Time to Live
* クライアントからVaultに対してシークレットの発行を依頼する

### MySQLの準備

ローカルのDocker上でMySQLを起動してください。

```shell
$ docker run --name mysql -e MYSQL_ROOT_PASSWORD=rooooot -p 3306:3306 -d mysql:5.7.22
```

rootでログインをしたら、サンプルのデータを投入します。パスワードは`rooooot`です。

```shell
$ mysql -u root -p -h127.0.0.1
```

```mysql
mysql> create database handson;
mysql> use handson;
mysql> create table products (id int, name varchar(50), price varchar(50));
mysql> insert into products (id, name, price) values (1, "Nice hoodie", "1580");
```

これでMySQLの準備は完了です。

<details><summary>Dockerではなくローカルで起動の場合はこちら</summary>

```console
$ sudo mysql.server start
Password:
Starting MySQL
.Logging to '/usr/local/var/mysql/Takayukis-MacBook-Pro.local.err'.
 SUCCESS!
 ```

> rootユーザのパスワードが設定されていない場合、以下のコマンドで変更してください。
> ```console
> $ mysql -u root
> ```
> 
> ```mysql
> mysql> ALTER USER 'root'@'localhost' IDENTIFIED BY 'rooooot';
> Query OK, 0 rows affected (0.00 sec)
> 
> mysql> exit
> ```
> 
> ```console
> $ sudo mysql.server restart
> ```

ログインを試してみてください。
```console
$ mysql -u root -p
```
</details>

### Vaultの設定

まずはデータベースへのコネクションの設定をVaultに行います。これ以降Vaultはこのパラメータを使ってユーザを払い出します。そのため強い権限のユーザを登録する必要があります。

```shell
$ vault write database/config/mysql-handson-db \
  plugin_name=mysql-legacy-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="role-handson" \
  username="root" \
  password="rooooot"
```

>ここでMySQLへのAccess Deniedでエラーになる方は下記のコマンドを実行してください。
>ここでのMySQLの再起動方法はOSによって異なります。
>```
>sudo mysql -u root -p
>mysql> USE mysql;
>mysql> UPDATE user SET plugin='mysql_native_password' WHERE User='root';
>mysql> FLUSH PRIVILEGES;
>mysql> exit;
>service mysql restart
>mysql login -p root
>mysql> ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'rooooot'; 
>service mysql restart
>```
`database/config/*****`はコンフィグの名前、任意に指定可能です。`plugin_name`は別途説明します。`allowed_roles`はこれから作成するユーザのロールの名前です。`allowed_roles`はList型になっており、一つのコンフィグに複数のロールを紐づけることが可能です。

次にロールの定義をします。

```shell
$ vault write database/roles/role-handson \
  db_name=mysql-handson-db \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON *.* TO '{{name}}'@'%';" \
  default_ttl="1h" \
  max_ttl="24h"
```

```console
$ vault list database/roles                         
Keys
----
role-handson
```

次に`/database/creds`のエンドポイントを使って、ロール名`role-handson`に基づいたシークレットを発行します。このエンドポイントが使われない限りシークレットは発行されません。通常この処理はクライアントから実行します。

```console
$ vault read database/creds/role-handson
Key                Value
---                -----
lease_id           database/creds/role-handson/nN0DRYCywFdU5Hjin0xLSGGs
lease_duration     1h
lease_renewable    true
password           A1a-P0cpPpKeKzdtv6hP
username           v-role-YpuDx1rjz
```

### MySQLにアクセスして権限を試す

次に発行したユーザを使ってMySQLサーバにアクセスしてみます。

```console 
$ mysql -u <USERNAME_GEN_BY_VAULT>  -h 127.0.0.1 -p handson
Enter password: <PASSWORD__GEN_BY_VAULT>
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 6
Server version: 5.7.25 Homebrew

Copyright (c) 2000, 2019, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> 
```

投入したデータを参照してみます。

```mysql
mysql> use handson;
mysql> show tables;
+-------------------+
| Tables_in_handson |
+-------------------+
| products          |
+-------------------+

mysql> select * from products;
+------+--------------+-------+
| id   | name         | price |
+------+--------------+-------+
|    1 | Nice hoodie  | 1580  |
+------+--------------+-------+

mysql> insert into products (id, name, price) values (1, "aaa", "bbb");
ERROR 1142 (42000): INSERT command denied to user 'v-role-InoM8WOwU'@'localhost' for table 'product'

mysql> create table test (id int, name varchar(10), price varchar(10));
ERROR 1142 (42000): CREATE command denied to user 'v-role-InoM8WOwU'@'localhost' for table 'test'
```

`select`の処理は実行出来ますが、そのほかの`insert`や`create table`の処理は権限上実行不可能なことがわかります。次はもう少し権限を絞ってみましょう。現在のロールは`GRANT SELECT ON *.*`とある通り、全てのデータベースと全てのテーブルに対して`select`の権限を与えています。

```mysql
mysql> use mysql;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+---------------------------+
| Tables_in_mysql           |
+---------------------------+
| columns_priv              |
| db                        |
| engine_cost               |
| event                     |
| func                      |
| general_log               |
| gtid_executed             |
| help_category             |
| help_keyword              |
~~~~~~~~~~~
```

次は該当のテーブルだけにアクセスできるロールを作ってみましょう。

```shell 
$ vault write database/config/mysql-handson-db \
  plugin_name=mysql-legacy-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="role-handson","role-handson-2" \
  username="root" \
  password="rooooot"
```

```shell
$ vault write database/roles/role-handson-2 \
  db_name=mysql-handson-db \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON handson.products TO '{{name}}'@'%';" \
  default_ttl="1h" \
  max_ttl="24h"
```

`allowed_roles`に`role-handson-2`を追加し、`role-handson-2`を作成しています。`GRANT SELECT ON handson.products`としています。

このロールを使ってユーザを発行してログインしてみます。

```console
$ vault read database/creds/role-handson-2
Key                Value
---                -----
lease_id           database/creds/role-handson-2/KXAWRvI0aawT9KObG3fVGLJo
lease_duration     1h
lease_renewable    true
password           A1a-8aBlTXjRSu9eR3y1
username           v-role-Ync7153K8

$ mysql -u <USERNAME_GEN_BY_VAULT>  -p                      
Enter password: <PASSWORD__GEN_BY_VAULT>
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 7
Server version: 5.7.25 Homebrew

Copyright (c) 2000, 2019, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql>
```

```mysql
mysql> show databases;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| handson            |
+--------------------+
2 rows in set (0.01 sec)
```

`handson`という名前のデータベースのみ権限があることがわかります。このような形でロールを定義し、必要な権限のユーザを必要な時に動的に生成することができます。次はシークレットの破棄を扱います。

### 動的シークレットの破棄

一つはTTLを設定した自動破棄です。短いTTLを設定した新しいロールを作ってみます。

```shell
$ vault write database/config/mysql-handson-db \
  plugin_name=mysql-legacy-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="role-handson","role-handson-2","role-handson-3" \
  username="root" \
  password="rooooot"
```
```shell
$ vault write database/roles/role-handson-3 \
  db_name=mysql-handson-db \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON handson.products TO '{{name}}'@'%';" \
  default_ttl="120s" \
  max_ttl="360s"
Success! Data written to: database/roles/role-handson
```

`max_ttl`のパラメータに120秒を指定しています。`default_ttl`生成した時のTTL、`max_ttl`は`renew`できる最大のTTLです。

このロールを利用してShort Livedなユーザを発行します。

```console
vault read database/creds/role-handson-3
Key                Value
---                -----
lease_id           database/creds/role-handson-3/H3y6DjZBGztisnO3B3DqzgkA
lease_duration     120s
lease_renewable    true
password           A1a-0VP1UDi5BPEMnPnZ
username           v-role-bnsYTFQAj
```

`lease_duration`が設定したTTLの120秒になっています。これを使ってまずは試しにログインしてみます。

```console
$ mysql -u <USERNAME_GEN_BY_VAULT> -p           
Enter password: <PASSWORD__GEN_BY_VAULT>
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 16
Server version: 5.7.25 Homebrew

Copyright (c) 2000, 2019, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> exit
Bye¥
```

30秒後に再度ログインします。

```console
$ mysql -u <USERNAME_GEN_BY_VAULT> -p        
Enter password: <PASSWORD__GEN_BY_VAULT>
ERROR 1045 (28000): Access denied for user 'v-role-bnsYTFQAj'@'localhost' (using password: YES)
```

ユーザが破棄され、利用不可能になりました。

2つ目の方法は`revoke`コマンドを使って明示的に破棄する方法です。`role-handson-2`のロールを使って新規のユーザを払い出します。払い出された`lease_id`をメモっておいてください。revokeの際に使用します。

```console
$ vault read database/creds/role-handson-2
Key                Value
---                -----
lease_id           database/creds/role-handson-2/JSnf6zV2jTrRJmI66Hfz189K
lease_duration     1h
lease_renewable    true
password           A1a-TaZktgzsQw4FfIT8
username           v-role-jklQMrcJa

$ mysql -u <USERNAME_GEN_BY_VAULT> -p -h 127.0.0.1 -p handson
Enter password: <PASSWORD__GEN_BY_VAULT>
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 22
Server version: 5.7.25 Homebrew

Copyright (c) 2000, 2019, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql>
```

`revoke`コマンドを実行してみます。

```console
$ vault lease revoke database/creds/role-handson-2/JSnf6zV2jTrRJmI66Hfz189K
All revocation operations queued successfully!

$ mysql -u <USERNAME_GEN_BY_VAULT> -p
Enter password: <PASSWORD__GEN_BY_VAULT>
ERROR 1045 (28000): Access denied for user 'v-role-jklQMrcJa'@'localhost' (using password: YES)
```

revokeされ、ログインが出来なくなりました。このようにVaultではシークレットを動的に生成し、短い時間でユーザを細かく破棄し、クレデンシャルをセキュアに保つ運用が簡単に実現できます。

## Rootユーザのパスワードローテーション

VaultにはRootユーザの権限を持たせる必要があるため、Rootユーザのパスワードの扱いは非常にセンシティブです。Vaultにはコンフィグレーションとして登録したデータベースのルートユーザのパスワードをローテーションさせるAPIを持っています。これを使ってこまめにRootのパスワードをリフレッシュできます。

**VaultによってRootパスワードのローテーションを行った後はRootのパスワードはVaultしか扱うことができません。そのため通常別の特権ユーザを準備してから行います。** 以下の手順はデフォルトのルートユーザをローテーションさせる手順のため、実施後Vaultからしか使えなくなります。こちらを実行するかはお任せします。

まず、`root_rotation_statements`のパラメータをコンフィグに追加してローテーションのAPIが呼ばれた時に実施する処理を記述します。

```shell
$ vault write database/config/mysql-handson-db \
  plugin_name=mysql-legacy-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="role-handson","role-handson-2","role-handson-3" \
  username="root" \
  password="rooooot" \
  root_rotation_statements="SET PASSWORD = PASSWORD('{{password}}')"
``` 

その後、`rotate-root`のAPIを実行するだけです。

```console
$ vault write -force database/rotate-root/mysql-handson-db
Success! Data written to: database/rotate-root/mysql-handson-db

$ mysql -u root -p
Enter password: rooooot
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)
```

古いRootパスワードは破棄され、利用不可能となりました。

## 参考リンク
* [API Documents](https://www.vaultproject.io/api/secret/databases/index.html)
* [Lease, Renew, and Revoke](https://www.vaultproject.io/docs/concepts/lease.html)
