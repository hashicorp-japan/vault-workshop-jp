# Vault AWS auth demo

Original project: [Vault Agent with AWS](https://learn.hashicorp.com/vault/identity-access-management/vault-agent-aws)

---
## 概要

VaultのAWSでのAuthenticationのデモになります。
デモの実行については、このRepoをCloneして[こちらのAsset](../asset/auth_aws)をご使用ください。

AWS auth methodについては、[こちら](https://www.vaultproject.io/docs/auth/aws.html)を参照ください。

AWS auth methodには２つのタイプがあります。`iam`と`ec2`の２種類です。
`iam`methodでは、IAMクレデンシャルでサインされた特別なAWSリクエストに対して認証を行います。IAMクレデンシャルはIAM instance profileやLambdaなどで自動的に作成されるので、AWS上のほぼ全てのサービスに対して利用できます。

`ec2`methodは、AWSがEC2インスタンスに自動的に付与するメタデータを用いて認証を行います。よって、この認証方法はEC2のインスタンスにしか利用できません。

`ec2`methodは`iam`methodの登場の前に開発されたもので、現在のベスト・プラクティスとしてはより柔軟かつ高度なアクセスコントロールのある`iam`methodを推奨しています。

このデモでは`iam`methodを用いています。

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
Terraformでプロビジョニングします。AWSのクレデンシャルを環境変数などに追加するのを忘れないでください。

```shell
$ export AWS_ACCESS_KEY_ID=xxxxxxxxxxxx
$ export AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxx

$ terraform init

$ terraform plan

# Output provides the SSH instruction
$ terraform apply -auto-approve
```

3. 以下のようなアウトプットが表示され、EC2に２つのインスタンスが出来上がっていれば成功です。

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

ここでは2つのインスタンスを作成しています。
一つは、Vault serverでもう一つはVault clientです。AWS認証を行なうVault Serverはどこに立ち上げても構いませんが（GCPやAzureでも可）、認証される側のClientはAWS上のインスタンスやサービスである必用があります（IAMロールが付随している必用があるため）。

これでデモのセットアップは完了です。

## Vault serverのセットアップ

まず、上記アウトプットに表示されるVault serverへsshで入ります。
そしてVaultが立ち上がっているか確認してください。

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

`vault status`コマンドでエラーがでなければVaultは正常に起動しています。ただ、この状態｀Initialized｀がFalseであり、`Sealed`はtrueになっています。つまり、Vaultは起動しているが、まだ初期化がされておらず、Seal状態であるということです。

それでは、次にVaultの初期化を行います。通常のVaultでは、初期化をするとShamirの分散鍵が生成され、それを用いてUnsealします。このデモではAWSのKMSを用いて**Auto unseal**を行います。Auto Unsealの設定方法は、Server上の`/etc/vault.d/vault.hcl`を参照ください。

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

ここで表示される**Initial Root Token**の値を必ずメモしてください。次にVaultの状態を確認します。

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

`vault operator init`で初期化されると、**Auto unseal**のおかげで自動的にVaultがUnseal状態になることが確認できます。(*Sealed = false*)

VaultのBackend storageにはConsulが設定されています。

```console
ubuntu@ip-10-0-101-67:~$ consul members
Node            Address           Status  Type    Build  Protocol  DC   Segment
ip-10-0-101-67  10.0.101.67:8301  alive   server  1.6.2  2         dc1  <all>
ip-10-0-101-96  10.0.101.96:8301  alive   client  1.6.2  2         dc1  <default>
ubuntu@ip-10-0-101-67:~$
```

consul serverがstorageとして使われ、それとは別にVault client側でもconsulがclientとしてクラスタが構築されています。

次にデモ用にシークレットエンジンとAuth methodを設定します。
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

このスクリプトでは、VaultのK/Vシークレットエンジンをマウントし、`secret/myapp/config`にシークレット情報を書き込んでいます。そして、そのシークレットにだけアクセス可能な**policy**を作成します。
さらに、AWS auth methodの認証も設定しています。Vault上に`dev-role-iam`というRoleを作成し、ここで指定したIAMロールのClientに対して、作成した`myapp`というpolicyを付与します。

このデモでは、Vault serverに紐付けられたIAMロール（この例では、_*arn:aws:iam::753278538983:role/masa-vault-auth-vault-client-role*)を用いてAWS auth methodを設定しています。もし別のIAMロールやIAMユーザーの権限で認証を行いたい場合は、以下のように個別に設定することも可能です。

```console
$ vault write auth/aws/config/client secret_key=vCtSM8ZUEQ3mOFVlYPBQkf2sO6F/W7a5TVzrl3Oj access_key=VKIAJBRHKH6EVTTNXDHA
```

またその場合、認証用のIAMポリシーは最低限以下の権限を与えてください。

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

それでは、スクリプトを実行してみます。Vaultコマンドの実行には、まず権限のあるTokenを用いてloginする必要があります。上記の`vault operator init`の際に作成された**Initial Root Token**でログインした上でスクリプトを実行します。

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

念の為、シークレットがちゃんと書き込まれたか確認します。Rootトークンでログインしているので、問題なく読み出しはできるはずです。

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

これでVault server側の設定は終わりです。

## Vault clientのセットアップ

それでは、Vault client側からAWS認証でVaultにアクセスし、シークレットの読み出しができるか確認してみましょう。

まず、Vault clientにsshでログインします。もし、Vault clientのIPアドレスが分からなくなった場合は、`terraform output`コマンドで確認してください。

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

`vault status`コマンドを叩いて、Vault serverつながっているか確認します。ちなみにVault serverは**VAULT_ADDR**という環境変数で指定されています。

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

まだ認証をしていないので、Tokenが無くエラーになります。
それでは、認証をしてみます。認証は`vault login`コマンドを使用します。

`vault login -method=aws role=dev-role-iam`

`-method=aws`でAWS認証を行うことを指定します。
｀role=dev-role-iam`でVault上のどのRoleのTokenを取得するか指定します。それでは実行してみましょう。

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

デモで実行したとおり、AWS認証を使うとAWS上のサービスやインスタンスで使用されるIAMロールを用いて簡単にVaultにアクセスすることができます。
これによりAWS上で動くインスタンやサービスは、アプリケーション内に認証用のシークレットを保管する必要がなくなり、またVault認証用のメカニズムも非常に簡単に導入することができます。
