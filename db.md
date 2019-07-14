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

ローカルでMySQLを起動してください。

```console
$ sudo mysql.server start
Password:
Starting MySQL
.Logging to '/usr/local/var/mysql/Takayukis-MacBook-Pro.local.err'.
 SUCCESS!
 ```

> rootユーザのパスワードが設定されていない場合、以下のコマンドで変更してください。
> ```console
> $ vault mysql -u root
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
> $ vault sudo mysql.server restart
> ```

rootでログインをしたら、サンプルのデータを投入します。

```mysql
mysql> create database handson;
mysql> create table products (id int, name varchar(10), price varchar(10));
mysql> insert into product (id, name, col) values (1, "Nice hoodie", "1580");
```

これでMySQLの準備は完了です。

### Vaultの設定

まずはデータベースへのコネクションの設定をVaultに行います。これ以降Vaultはこのパラメータを使ってユーザを払い出します。そのため強い権限のユーザを登録する必要があります。

```console
$ vault write database/config/mysql-handson-db \
  plugin_name=mysql-legacy-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="role-handson" \
  username="root" \
  password="rooooot"
```

`database/config/*****`はコンフィグの名前、任意に指定可能です。`plugin_name`は別途説明します。`allowed_roles`はこれから作成するユーザのロールの名前です。`allowed_roles`はList型になっており、一つのコンフィグに複数のロールを紐づけることが可能です。

次にロールの定義をします。

```console
$ vault write database/roles/role-handson \
    db_name=mysql-handson-db \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON *.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"
Success! Data written to: database/roles/role-handson

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
$ mysql -u v-role-YpuDx1rjz -p
Enter password:
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

mysql> insert into product (id, name, price) values (1, "aaa", "bbb");
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
mysql> show tables
    -> ;
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

```console
$ vault write database/config/mysql-handson-db \ 
  plugin_name=mysql-legacy-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="role-handson","role-handson-2" \
  username="root" \
  password="rooooot"

$ vault write database/roles/role-handson−2 \
    db_name=mysql-handson-db \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON handson.product TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"
Success! Data written to: database/roles/role-handson
```

`allowed_roles`に`role-handson-2`を追加し、`role-handson-2`を作成しています。。`GRANT SELECT ON handson.product`としています。

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

$ mysql -u v-role-Ync7153K8  -p                              kabu@/Users/kabu
Enter password:
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



## 参考リンク
* [API Documents](https://www.vaultproject.io/api/secret/databases/index.html)