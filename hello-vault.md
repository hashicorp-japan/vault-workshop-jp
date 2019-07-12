# 初めてのVault

ここではまずVaultのインストール、unsealと初めてのシークレットを作ってみます。

## Vaultのインストール

[こちら](https://www.vaultproject.io/downloads.html)のWebサイトからご自身のOSに合ったものをダウンロードしてください。

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

