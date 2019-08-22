# SSHシークレットエンジンを使ってワンタイムSSHパスワードを利用する

VaultのSSHシークレットエンジンではSSHを使ったマシンへのアクセスのセキュアな認証認可を提供します。Vaultを利用することで複雑なSSHクレデンシャルのライフサイクル管理のワークフローをよりシンプルにセキュアに実施できます。SSHシークレットエンジンの主な機能は以下の二つです。

* Singed SSH Certificates
* One-time SSH Paswords

ここでは両方を簡単に試してみます。

この章ではローカルに立ち上がっているVaultと仮想マシンを通信させるため、Vaultのコンフィグを以下のように変更し再起動します。`Ctrl+C`でVaultの端末を止めて以下のようにファイルを変更してください。

```hcl
storage "file" {
   path = "/Users/Shared/vault-oss-data"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

listener "tcp" {
  address     = "192.168.11.2:8200"
  tls_disable = 1
}

seal "awskms" {
  region     = "ap-northeast-1"
  endpoint   = "https://kms.ap-northeast-1.amazonaws.com"
}

api_addr = "http://192.168.11.2:8200"

ui = true
```

`192.168.11.2:8200`のIPはぞれぞれの環境に合わせてください。これで再度起動します。

```shell
$ vault server -config=path/to/vault-local-config.hcl start
```

## Singed SSH Certificates

### クライアントキーサイン

公開鍵認証の場合サーバに対する秘密鍵を共有したり、キーペアをそれぞれに持たせて運用が複雑化する課題がありますがCA認証によりこれらを解決でき、かつVaultがCAとして機能することで非常にシンプルなワークフローで実現できます。公開鍵認証とCA認証の一般的な流れは下記の通りです。

[公開鍵認証]
<kbd>
  <img src="https://github-image-tkaburagi.s3-ap-northeast-1.amazonaws.com/vault-workshop/puflow.png">
</kbd>

[CA認証]
<kbd>
  <img src="https://github-image-tkaburagi.s3-ap-northeast-1.amazonaws.com/vault-workshop/caflow-with-number.png">
</kbd>

まずいつものようにVaultのSSHシークレットエンジンを有効化しましょう。

```shell
vault secrets enable -path=ssh ssh
```

### CAの設定

図の①の手順です。

まず、VaultをCAとして設定します。`generate_signing_key`を指定することでこのタイミングでサイン用のキーペアーを発行できます。既存にある場合は`private_key`, `public_key`のパラメータの引数としてセットします。

ここでは`generate_signing_key`を付与して生成してみます。

```shell
vault write ssh-client-signer/config/ca generate_signing_key=true
```

Public Keyのみが出力されるでしょう。

次にVault上に、SSHでログインするユーザに与える権限と認証のタイプを指定します。

```shell
$ export VAULT_ADDR="http://192.168.11.2:8200"
```

```
$ vault write ssh/roles/my-role -<<"EOH"
{
  "allow_user_certificates": true,
  "allowed_users": "ubuntu",
  "default_extensions": [
    {
      "permit-pty": ""
    }
  ],
  "key_type": "ca",
  "default_user": "ubuntu",
  "ttl": "30m0s"
}
EOH
```

`key_type`は他に`otp`と`dynamic`を指定することができ、`otp`はこのあと扱います。

### サイン用公開鍵の配布

図の②の手順です。

次に、この公開鍵をターゲットとなるホスト(VM)のSSHコンフィグレーションに配布します。(図の②)

Vagrantを使ってUbuntu OSのVMを一つ起動してみましょう。適当なディレクトリを作ります。

```shell
$ mkdir -p ~/vagrant/ubuntu
$ cd ~/vagrant/ubuntu
$ vagrant box add ubuntu14.04 https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box
$ vagrant init ubuntu14.04
```

`Vagrantfile`の以下の行のコメントは外してください。

```
# config.vm.network "public_network"
```

```console
$ vagrant up

Bringing machine 'default' up with 'virtualbox' provider...
==> default: Importing base box 'ubuntu14.04'...
==> default: Matching MAC address for NAT networking...
==> default: Setting the name of the VM: ubuntu_default_1564553548030_13754
==> default: Clearing any previously set forwarded ports...
==> default: Clearing any previously set network interfaces...
==> default: Available bridged network interfaces:
1) en0: Wi-Fi (Wireless)
2) ap1
3) p2p0
4) awdl0
5) en2: Thunderbolt 2
6) en4: Thunderbolt 4
7) en1: Thunderbolt 1
8) en3: Thunderbolt 3
9) bridge0
10) en5: USB Ethernet(?)
==> default: When choosing an interface, it is usually the one that is
==> default: being used to connect to the internet.
    default: Which interface should the network bridge to? 1
==> default: Preparing network interfaces based on configuration...
    default: Adapter 1: nat
    default: Adapter 2: bridged
==> default: Forwarding ports...
    default: 22 (guest) => 2222 (host) (adapter 1)
==> default: Booting VM...
==> default: Waiting for machine to boot. This may take a few minutes...
    default: SSH address: 127.0.0.1:2222
    default: SSH username: vagrant
    default: SSH auth method: private key


    default:
    default: Vagrant insecure key detected. Vagrant will automatically replace
    default: this with a newly generated keypair for better security.
    default:
    default: Inserting generated public key within guest...
    default: Removing insecure key from the guest if it's present...
    default: Key inserted! Disconnecting and reconnecting using new SSH key...
==> default: Machine booted and ready!
==> default: Checking for guest additions in VM...
    default: The guest additions on this VM do not match the installed version of
    default: VirtualBox! In most cases this is fine, but in rare cases it can
    default: prevent things such as shared folders from working properly. If you see
    default: shared folder errors, please make sure the guest additions within the
    default: virtual machine match the version of VirtualBox you have installed on
    default: your host and reload your VM.
    default:
    default: Guest Additions Version: 4.3.40
    default: VirtualBox Version: 6.0
==> default: Configuring and enabling network interfaces...
==> default: Mounting shared folders...
    default: /vagrant => /Users/kabu/vagrant/ubuntu
```

起動しました。今後このVMのことを「ホスト」、ローカルマシンのことを「クライアント」と呼びます。

ホストに`vagrant ssh`でログインします。以下のコマンドでVaultで生成したpublic_keyを取得します。

```shell
$ sudo curl -o /etc/ssh/trusted-user-ca-keys.pem http://192.168.11.2:8200/v1/ssh/public_key
```

`192.168.11.2`はローカルのVaultのアドレスです。

```console
$ cat /etc/ssh/trusted-user-ca-keys.pem
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABA.....
```

これを`sshd_config`に配備します。

```console
$ sudo sed -i '$a TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem' /etc/ssh/sshd_config
$ sudo service ssh restart
```

今回はVaultサーバとクライアントがローカルマシンで同居しているのでわかりづらいかもしれませんが、Vaultを起動しているローカルマシンで以下を実行します。

### クライアント側の設定

クライアントでキーペアを作成します。図の③の手順です。
```shell
$ ssh-keygen -t 
```

生成された公開鍵をVault(CA)に渡してサインのリクエストをし、サイン済みの公開鍵(証明書)を発行します。

```shell
$ vault write -field=signed_key ssh/sign/my-role \
    public_key=@$HOME/.ssh/id_rsa.pub > signed-cert.pub
```

出力される`signed_key`がそれに当たります。

証明書の内容を確認してみましょう。

```shell
ssh-keygen -Lf ~/.ssh/signed-cert.pub
```

`Valid`の欄がRoleで指定した30minsのTTLになっているはずです。

最後にこれを使ってSSHでサーバにアクセスしてみましょう。

```shell
ssh -i signed-cert.pub -i ~/.ssh/id_rsa ubuntu@192.168.11.9
```

`ubuntu`ユーザでログインできるはずです。

この証明書は30分後に無効となりログインが不可能になります。また、`revoke`を行うことで明示的に無効にできます。

このようにCA認証を簡単に利用することができるため、環境やチームが拡大するにつれて複雑化する運用を効率化することができます。

## One-time SSH Paswords

次はSSHシークレットエンジンの二つ目のユースケースであるワンタイムパスワード(OTP)を扱います。

クラウド化が進むにつれ、オンラインセキュリティの重要度は増しています。アタッカーがVMへのアクセスを入手するとあらゆるデータやサービスへのアクセスを許すこととなり、SSHキーの扱いは非常に重要です。

ワークフローは下記の通りです。

* 認証されたVaultのクライアントがVaultに対してOTPの発行を依頼
* VaultによりOTPの発行と提供
* クライアントはSSHコネクションの間そのOTPを利用しホストに接続
* クライアントがホストに接続したことを確認するとVaultがそのパスワードを消去

まずはホスト側の準備をします。VaultのOTPを利用するには全てのホスト側で[`vault-ssh-helper`](https://github.com/hashicorp/vault-ssh-helper)をインストールする必要があります。

ホストに`vagrant ssh`でログインして以下のコマンドを実行します。

```shell
$ wget https://releases.hashicorp.com/vault-ssh-helper/0.1.4/vault-ssh-helper_0.1.4_linux_amd64.zip
$ sudo unzip -q vault-ssh-helper_0.1.4_linux_amd64.zip -d /usr/local/bin
$ sudo chmod 0755 /usr/local/bin/vault-ssh-helper
$ sudo chown root:root /usr/local/bin/vault-ssh-helper
```

`/etc/vault-ssh-helper.d/config.hcl`のファイルを作り、下記のように編集します。

```hcl
vault_addr = "http://<LOCAL_VAULT_ADDR>:8200"
ssh_mount_point = "ssh"
allowed_roles = "*"
```

`/etc/pam.d/sshd`を編集します。変更部分は`Standard Un*x authentication.`から数行ですが、ミスを防ぐために[こちらを参照して](https://github.com/tkaburagi/vault-configs/blob/master/sshd)全て上書きしてください。

次に`/etc/ssh/sshd_config`の最後の行に以下を追加してsshdを再起動します。

```
ChallengeResponseAuthentication yes
PasswordAuthentication no
UsePAM yes
```

```shell
$ sudo service ssh restart
```

次にVault側の設定です。

先ほど有効にした`ssh`エンドポイントを利用します。`ssh/roles/<NAME>`のエンドポイントでロールを作ります。

```shell
$ vault write ssh/roles/otp_key_role key_type=otp \
        default_user=ubuntu \
        cidr_list=0.0.0.0/0
```

次にクライアントトークンに紐付けるポリシーを設定します。クラアイントは上記で定義したロールのOTPを発行するだけなので、`ssh/roles/otp_key_role`に対する権限だけあればOKです。

`vault-ssh-otp-policy.hcl`のファイルを作り下記のように編集します。

```hcl
path "ssh/creds/otp_key_role" {
  capabilities = [ "create","update","read" ]
}
```

```console
$ vault policy write ssh-otp-client-policy path/to/vault-ssh-otp-policy.hcl
$ vault token create -policy=ssh-otp-client-policy -ttl=15m

Key                  Value
---                  -----
token                s.9nifyTTs49Mu73HMZffWBFVU
token_accessor       fkIZ2hWU0dMyQ2CbgaK55xfk
token_duration       15m
token_renewable      true
token_policies       ["default" "ssh-otp-client-policy"]
identity_policies    []
policies             ["default" "ssh-otp-client-policy"]
```

ここからはクライアントの手順です。クライアントは上記のトークンを使って、OTPの発行をVaultに依頼します。

```console
$ VAULT_TOKEN=s.9nifyTTs49Mu73HMZffWBFVU vault write ssh/creds/otp_key_role ip=<HOST's IP>

Key                Value
---                -----
lease_id           ssh/creds/otp_key_role/HmJV2vzyGf7bT2Mh6oB7qeyo
lease_duration     768h
lease_renewable    false
ip                 192.168.11.9
key                49ae44c0-298f-02d2-c8a3-2c1d8fbaee1c
key_type           otp
port               22
username           ubuntu
```

ubuntuユーザ用のOTPが発行されました。これでログインしてみます。`key`がパスワードです。

```console
$ ssh ubuntu@192.168.11.9
ubuntu@192.168.11.9's password: 49ae44c0-298f-02d2-c8a3-2c1d8fbaee1c

Welcome to Ubuntu 14.04.6 LTS (GNU/Linux 3.13.0-170-generic x86_64)

 * Documentation:  https://help.ubuntu.com/

  System information as of Thu Aug  1 03:02:18 UTC 2019

  System load:  0.05              Processes:           79
  Usage of /:   3.6% of 39.34GB   Users logged in:     1
  Memory usage: 27%               IP address for eth0: 10.0.2.15
  Swap usage:   0%                IP address for eth1: 192.168.11.9

  Graph this data and manage this system at:
    https://landscape.canonical.com/

New release '16.04.6 LTS' available.
Run 'do-release-upgrade' to upgrade to it.


Last login: Thu Aug  1 03:02:18 2019 from 192.168.11.2
ubuntu@vagrant-ubuntu-trusty-64:~$ whoami
ubuntu
ubuntu@vagrant-ubuntu-trusty-64:~$ exit
```

`exit`を実行して抜けてみましょう。再度ログインをしてみます。

```console
$ ssh ubuntu@192.168.11.9
ubuntu@192.168.11.9's password: 49ae44c0-298f-02d2-c8a3-2c1d8fbaee1c
Permission denied, please try again.
ubuntu@192.168.11.9's password: 49ae44c0-298f-02d2-c8a3-2c1d8fbaee1c
Permission denied, please try again.
```

Vaultにより無効化されました。

## 参考リンク
* [SSH Secret Engine](https://www.vaultproject.io/docs/secrets/ssh/index.html)
* [API Document](https://www.vaultproject.io/api/secret/ssh/index.html)
* [Vault SSH Helper](https://github.com/hashicorp/vault-ssh-helper)
* [公開鍵認証とCA認証](http://kontany.net/blog/?p=211)
