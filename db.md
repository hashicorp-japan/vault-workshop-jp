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



## 参考リンク
* [API Documents](https://www.vaultproject.io/api/secret/databases/index.html)