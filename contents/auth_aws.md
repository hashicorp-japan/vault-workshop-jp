# Vault AWS auth demo

Original project: [Vault Agent with AWS](https://learn.hashicorp.com/vault/identity-access-management/vault-agent-aws)

---
## 概要

Vault の AWS での Authentication のデモになります。
デモの実行については、この Repo を Clone して[こちらの Asset](../assets/auth_aws)をご使用ください。

AWS auth method については、[こちら](https://www.vaultproject.io/docs/auth/aws.html)を参照ください。

AWS auth method には２つのタイプがあります。`iam`と`ec2`の２種類です。
`iam`method では、IAM クレデンシャルでサインされた特別な AWS リクエストに対して認証を行います。IAM クレデンシャルは IAM instance profile や Lambda などで自動的に作成されるので、AWS 上のほぼ全てのサービスに対して利用できます。

`ec2`method は、AWS が EC2 インスタンスに自動的に付与するメタデータを用いて認証を行います。よって、この認証方法は EC2 のインスタンスにしか利用できません。

`ec2`method は`iam`method の登場の前に開発されたもので、現在のベスト・プラクティスとしてはより柔軟かつ高度なアクセスコントロールのある`iam`method を推奨しています。

このデモでは`iam`method を用いています。

## Demo setup

1.
まずは、`terraform.tfvars.example`を`terraform.tfvars`と変名して、中身を環境に合わせて変更してください。
変更してほしいもの：
* key_name
* aws_region
* availabiliy_zones

```hcl
#-------------------
# Required: こちらを各自の環境に合わせて変更ください
#-------------------

# SSH key name to access EC2 instances. This should already exist in the AWS Region
key_name = "MY_EC2_KEY_NAME"

# AWS region & AZs
aws_region = "ap-northeast-1"
availability_zones = "ap-northeast-1a"

#-----------------------------------------------
# Optional: To overwrite the default settings
#-----------------------------------------------

# All resources will be tagged with this (default is 'vault-agent-demo')
environment_name = "vault-agent-demo"

# Instance size (default is t2.micro)
instance_type = "t2.micro"

# Number of Vault servers to provision (default is 1)
vault_server_count = 1
```

2.
Terraform でプロビジョニングします。AWS のクレデンシャルを環境変数などに追加するのを忘れないでください。

```shell
$ export AWS_ACCESS_KEY_ID=xxxxxxxxxxxx
$ export AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxx

$ terraform init

$ terraform plan

# Output provides the SSH instruction
$ terraform apply -auto-approve
```

3. 以下のようなアウトプットが表示され、EC2 に２つのインスタンスが出来上がっていれば成功です。

```console
Apply complete! Resources: 20 added, 0 changed, 0 destroyed.

Outputs:

endpoints =
Vault Server IP (public):  3.112.22.241
Vault Server IP (private): 10.0.101.67

For example:
   ssh -i masa.pem ubuntu@3.112.22.241

Vault Client IP (public):  13.115.119.242
Vault Client IP (private): 10.0.101.96

For example:
   ssh -i masa.pem ubuntu@13.115.119.242

Vault Client IAM Role ARN: arn:aws:iam::753278538983:role/masa-vault-auth-vault-client-role
```

ここでは 2 つのインスタンスを作成しています。
一つは、Vault server でもう一つは Vault client です。AWS 認証を行なう Vault Server はどこに立ち上げても構いませんが（GCP や Azure でも可）、認証される側の Client は AWS 上のインスタンスやサービスである必用があります（IAM ロールが付随している必用があるため）。

これでデモのセットアップは完了です。

## Vault server のセットアップ

まず、上記アウトプットに表示される Vault server へ ssh で入ります。
そして Vault が立ち上がっているか確認してください。

```console
$ ssh ubuntu@3.112.22.241
Welcome to Ubuntu 18.04.3 LTS (GNU/Linux 4.15.0-1054-aws x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Fri Dec 13 02:12:26 UTC 2019

  System load:  0.0               Processes:           89
  Usage of /:   21.0% of 7.69GB   Users logged in:     0
  Memory usage: 28%               IP address for eth0: 10.0.101.67
  Swap usage:   0%


39 packages can be updated.
15 updates are security updates.


Last login: Fri Dec 13 02:07:30 2019 from 126.140.246.218
-bash: warning: setlocale: LC_ALL: cannot change locale (ja_JP.UTF-8)
To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

ubuntu@ip-10-0-101-67:~$ which vault
/usr/local/bin/vault
ubuntu@ip-10-0-101-67:~$ vault version
Vault v1.3.0
ubuntu@ip-10-0-101-67:~$ vault status
Key                      Value
---                      -----
Recovery Seal Type       awskms
Initialized              false
Sealed                   true
Total Recovery Shares    0
Threshold                0
Unseal Progress          0/0
Unseal Nonce             n/a
Version                  n/a
HA Enabled               true
ubuntu@ip-10-0-101-67:~$
```

`vault status`コマンドでエラーがでなければ Vault は正常に起動しています。ただ、この状態｀Initialized｀が False であり、`Sealed`は true になっています。つまり、Vault は起動しているが、まだ初期化がされておらず、Seal 状態であるということです。

それでは、次に Vault の初期化を行います。通常の Vault では、初期化をすると Shamir の分散鍵が生成され、それを用いて Unseal します。このデモでは AWS の KMS を用いて**Auto unseal**を行います。Auto Unseal の設定方法は、Server 上の`/etc/vault.d/vault.hcl`を参照ください。

```console
ubuntu@ip-10-0-101-67:~$ vault operator init
Recovery Key 1: 2bxJ0k7+lpoK8o6MAj7ebecIzh9V5d2n9L0GfWyUJjmn
Recovery Key 2: ElH9q/dkglVjFG8mfIZbriM8zbo1C1/JWH12j1R1L45j
Recovery Key 3: c9THb228rV++VUCTkyDjMUw0IG1LyKiaUa3ZmJzyq9oM
Recovery Key 4: EdhT6w6QKGCxtmuU8HSFbcSA/FXYYSHJ//fRF8UiD2+E
Recovery Key 5: s0APWYiXE6KMadHbwCbBWuTzL8CCUa5WnZOW5obGjM6k

Initial Root Token: s.Vfj4S1Wx5bFY5xms5eF751pr

Success! Vault is initialized

Recovery key initialized with 5 key shares and a key threshold of 3. Please
securely distribute the key shares printed above.
```

ここで表示される**Initial Root Token**の値を必ずメモしてください。次に Vault の状態を確認します。

```console
ubuntu@ip-10-0-101-67:~$ vault status
Key                      Value
---                      -----
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.3.0
Cluster Name             vault-cluster-918e85f6
Cluster ID               b135ecb7-0328-a361-8781-d9db57a876b5
HA Enabled               true
HA Cluster               https://10.0.101.67:8201
HA Mode                  active
ubuntu@ip-10-0-101-67:~$
```

`vault operator init`で初期化されると、**Auto unseal**のおかげで自動的に Vault が Unseal 状態になることが確認できます。(*Sealed = false*)

Vault の Backend storage には Consul が設定されています。

```console
ubuntu@ip-10-0-101-67:~$ consul members
Node            Address           Status  Type    Build  Protocol  DC   Segment
ip-10-0-101-67  10.0.101.67:8301  alive   server  1.6.2  2         dc1  <all>
ip-10-0-101-96  10.0.101.96:8301  alive   client  1.6.2  2         dc1  <default>
ubuntu@ip-10-0-101-67:~$
```

consul server が storage として使われ、それとは別に Vault client 側でも consul が client としてクラスタが構築されています。

次にデモ用にシークレットエンジンと Auth method を設定します。
ホームディレクトリにある`aws_auth.sh`を見てください。

```shell
vault secrets enable -path="secret" kv
vault kv put secret/myapp/config ttl='30s' username='appuser' password='suP3rsec(et!'

echo "path \"secret/myapp/*\" {
    capabilities = [\"read\", \"list\"]
}" | vault policy write myapp -

vault auth enable aws
vault write -force auth/aws/config/client

vault write auth/aws/role/dev-role-iam auth_type=iam bound_iam_principal_arn="arn:aws:iam::753278538983:role/masa-vault-auth-vault-client-role" policies=myapp ttl=24h
```

このスクリプトでは、Vault の K/V シークレットエンジンをマウントし、`secret/myapp/config`にシークレット情報を書き込んでいます。そして、そのシークレットにだけアクセス可能な**policy**を作成します。
さらに、AWS auth method の認証も設定しています。Vault 上に`dev-role-iam`という Role を作成し、ここで指定した IAM ロールの Client に対して、作成した`myapp`という policy を付与します。

このデモでは、Vault server に紐付けられた IAM ロール（この例では、_*arn:aws:iam::753278538983:role/masa-vault-auth-vault-client-role*)を用いて AWS auth method を設定しています。もし別の IAM ロールや IAM ユーザーの権限で認証を行いたい場合は、以下のように個別に設定することも可能です。

```console
$ vault write auth/aws/config/client secret_key=vCtSM8ZUEQ3mOFVlYPBQkf2sO6F/W7a5TVzrl3Oj access_key=VKIAJBRHKH6EVTTNXDHA
```

またその場合、認証用の IAM ポリシーは最低限以下の権限を与えてください。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "iam:GetInstanceProfile",
        "iam:GetUser",
        "iam:GetRole"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["sts:AssumeRole"],
      "Resource": [
        "arn:aws:iam::<AccountId>:role/<VaultRole>"
      ]
    }
  ]
}
```

それでは、スクリプトを実行してみます。Vault コマンドの実行には、まず権限のある Token を用いて login する必要があります。上記の`vault operator init`の際に作成された**Initial Root Token**でログインした上でスクリプトを実行します。

```console
ubuntu@ip-10-0-101-67:~$ vault login s.Vfj4S1Wx5bFY5xms5eF751pr
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.Vfj4S1Wx5bFY5xms5eF751pr
token_accessor       dqYhASeH7qdTh0acArOE8Cgu
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]

ubuntu@ip-10-0-101-67:~$ ./aws_auth.sh
Success! Enabled the kv secrets engine at: secret/
Success! Data written to: secret/myapp/config
Success! Uploaded policy: myapp
Success! Enabled aws auth method at: aws/
Success! Data written to: auth/aws/config/client
Success! Data written to: auth/aws/role/dev-role-iam
ubuntu@ip-10-0-101-67:~$
```

念の為、シークレットがちゃんと書き込まれたか確認します。Root トークンでログインしているので、問題なく読み出しはできるはずです。

```console
ubuntu@ip-10-0-101-67:~$ vault read secret/myapp/config
Key                 Value
---                 -----
refresh_interval    30s
password            suP3rsec(et!
ttl                 30s
username            appuser
ubuntu@ip-10-0-101-67:~$
```

これで Vault server 側の設定は終わりです。

## Vault client のセットアップ

それでは、Vault client 側から AWS 認証で Vault にアクセスし、シークレットの読み出しができるか確認してみましょう。

まず、Vault client に ssh でログインします。もし、Vault client の IP アドレスが分からなくなった場合は、`terraform output`コマンドで確認してください。

```console
$ terraform output
endpoints =
Vault Server IP (public):  3.112.22.241
Vault Server IP (private): 10.0.101.67

For example:
   ssh -i masa.pem ubuntu@3.112.22.241

Vault Client IP (public):  13.115.119.242
Vault Client IP (private): 10.0.101.96

For example:
   ssh -i masa.pem ubuntu@13.115.119.242

Vault Client IAM Role ARN: arn:aws:iam::753646501470:role/masa-vault-auth-vault-client-role
```

ログインします。

```console
$ ssh ubuntu@13.115.119.242
The authenticity of host '13.115.119.242 (13.115.119.242)' can't be established.
ECDSA key fingerprint is SHA256:UYqchHgw3mg1x9QEGz1OY/eyD00Not8UI5Ptr2H1lVc.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '13.115.119.242' (ECDSA) to the list of known hosts.
Welcome to Ubuntu 18.04.3 LTS (GNU/Linux 4.15.0-1054-aws x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Fri Dec 13 02:54:11 UTC 2019

  System load:  0.0               Processes:           88
  Usage of /:   21.0% of 7.69GB   Users logged in:     0
  Memory usage: 18%               IP address for eth0: 10.0.101.96
  Swap usage:   0%

36 packages can be updated.
15 updates are security updates.



The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

-bash: warning: setlocale: LC_ALL: cannot change locale (ja_JP.UTF-8)
To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

ubuntu@ip-10-0-101-96:~$
```

`vault status`コマンドを叩いて、Vault server つながっているか確認します。ちなみに Vault server は**VAULT_ADDR**という環境変数で指定されています。

```console
ubuntu@ip-10-0-101-96:~$ vault status
Key                      Value
---                      -----
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.3.0
Cluster Name             vault-cluster-918e85f6
Cluster ID               b135ecb7-0328-a361-8781-d9db57a876b5
HA Enabled               true
HA Cluster               https://10.0.101.67:8201
HA Mode                  active

ubuntu@ip-10-0-101-96:~$ echo $VAULT_ADDR
http://10.0.101.67:8200
```

この状態でシークレットが読み出せるか試してみます。

```console
ubuntu@ip-10-0-101-96:~$ vault read secret/myapp/config
Error reading secret/myapp/config: Error making API request.

URL: GET http://10.0.101.67:8200/v1/secret/myapp/config
Code: 400. Errors:

* missing client token
```

まだ認証をしていないので、Token が無くエラーになります。
それでは、認証をしてみます。認証は`vault login`コマンドを使用します。

`vault login -method=aws role=dev-role-iam`

`-method=aws`で AWS 認証を行うことを指定します。
｀role=dev-role-iam`で Vault 上のどの Role の Token を取得するか指定します。それでは実行してみましょう。

```console
ubuntu@ip-10-0-101-96:~$ vault login -method=aws role=dev-role-iam
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                                Value
---                                -----
token                              s.3BiCdXIBpmRf68iFi1wXnj6i
token_accessor                     7zJFSroWIDCNeDvfZhphhe1o
token_duration                     24h
token_renewable                    true
token_policies                     ["default" "myapp"]
identity_policies                  []
policies                           ["default" "myapp"]
token_meta_canonical_arn           arn:aws:iam::753646501470:role/masa-vault-auth-vault-client-role
token_meta_client_arn              arn:aws:sts::753646501470:assumed-role/masa-vault-auth-vault-client-role/i-0b0810e63d1d081ec
token_meta_inferred_entity_id      n/a
token_meta_inferred_entity_type    n/a
token_meta_account_id              753646501470
token_meta_auth_type               iam
token_meta_client_user_id          AROA266GU7ZPL673XWQ72
token_meta_inferred_aws_region     n/a
token_meta_role_id                 32a51eb5-6448-4222-c5e0-400709344741
ubuntu@ip-10-0-101-96:~$
```

認証が成功し、`token                              s.3BiCdXIBpmRf68iFi1wXnj6i`が返ってきました。

ここで再度、シークレットの読み出しをしてみます。

```console
ubuntu@ip-10-0-101-96:~$ vault read secret/myapp/config
Key                 Value
---                 -----
refresh_interval    30s
password            suP3rsec(et!
ttl                 30s
username            appuser
```

今回は読み出しに成功しました。

## Takeaways

デモで実行したとおり、AWS 認証を使うと AWS 上のサービスやインスタンスで使用される IAM ロールを用いて簡単に Vault にアクセスすることができます。
これにより AWS 上で動くインスタンやサービスは、アプリケーション内に認証用のシークレットを保管する必要がなくなり、また Vault 認証用のメカニズムも非常に簡単に導入することができます。
