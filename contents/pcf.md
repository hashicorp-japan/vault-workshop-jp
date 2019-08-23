# Pivotal Cloud FoundryからVaultのシークレットを扱う

Kuberneteと同様Pivotal Cloud Foundry (以下PCF)ともいくつかの連携パターンがあります。

* PCFを利用したVault認証
* PCF上のアプリからVaultを介したシークレットの利用

## Vault Service Brokerを利用する

PCFからVaultのシークレットを扱う際は[Vault Service Broker](https://github.com/hashicorp/vault-service-broker)を使うと便利です。

Service Brokerを利用することで`cf cli`でVaultのTokenを払い出し、アプリにセットすることが可能です。

ここでは[Pivotal Web Service](https://run.pivotal.io/)(以下PWS)を利用します。無料でも利用できます。

Sign-upが済んだらPWSにログインしましょう。

```shell
$ cf login -a api.run.pivotal.io -u ********** -p **********
```

### VaultをPWS上にデプロイ

PWS上のアプリとService Brokerと通信できるVaultインスタンスが必要なため、VaultをPWS上にデプロイしてしまいます。

[この記事](https://blog.ik.am/entries/423)を参考にしています。

```shell
$ mkdir cf-vault
cd cf-vault
```

ここではVaultとStorage BackendとしてPWS上のClearDBを使います。

```shell
$ cf create-service cleardb spark vault-db
```

以下のファイルを作ります。

<details><summary>run.sh</summary>

```shell
#!/bin/sh

CLEARDB=`echo $VCAP_SERVICES | grep "cleardb"`
PMYSQL=`echo $VCAP_SERVICES | grep "p-mysql"`

if [ "$CLEARDB" != "" ];then
	SERVICE="cleardb"
elif [ "$PMYSQL" != "" ]; then
	SERVICE="p-mysql"
fi

echo "detected $SERVICE"

HOSTNAME=`echo $VCAP_SERVICES | jq -r '.["'$SERVICE'"][0].credentials.hostname'`
PASSWORD=`echo $VCAP_SERVICES | jq -r '.["'$SERVICE'"][0].credentials.password'`
PORT=`echo $VCAP_SERVICES | jq -r '.["'$SERVICE'"][0].credentials.port'`
USERNAME=`echo $VCAP_SERVICES | jq -r '.["'$SERVICE'"][0].credentials.username'`
DATABASE=`echo $VCAP_SERVICES | jq -r '.["'$SERVICE'"][0].credentials.name'`

cat <<EOF > cf.hcl
disable_mlock = true
ui = true
storage "mysql" {
  username = "$USERNAME"
  password = "$PASSWORD"
  address = "$HOSTNAME:$PORT"
  database = "$DATABASE"
  table = "vault"
  max_parallel = 4
}
listener "tcp" {
 address = "0.0.0.0:8080"
 tls_disable = 1
}
EOF

echo "#### Starting Vault..."

./vault server -config=cf.hcl &

if [ "$VAULT_UNSEAL_KEY1" != "" ];then
	export VAULT_ADDR='http://127.0.0.1:8080'
	echo "#### Waiting..."
	sleep 1
	echo "#### Unsealing..."
	if [ "$VAULT_UNSEAL_KEY1" != "" ];then
		./vault unseal $VAULT_UNSEAL_KEY1
	fi
	if [ "$VAULT_UNSEAL_KEY2" != "" ];then
		./vault unseal $VAULT_UNSEAL_KEY2
	fi
	if [ "$VAULT_UNSEAL_KEY3" != "" ];then
		./vault unseal $VAULT_UNSEAL_KEY3
	fi
fi
```
</details>

Vaultをダウンロードして必要な権限を与えます。

```console
$ wget https://releases.hashicorp.com/vault/1.2.2/vault_1.2.2_linux_amd64.zip
$ unzip vault_1.2.2_linux_amd64.zip
$ chmod +x vault
$ chmod +x run.sh
```

最後にmanifestを作ります。`NAME`は適当に置き換えてください。

```shell
$ cat <<EOF > manifest.yml
applications:
- name: cf-vault-NAME
  buildpack: binary_buildpack
  memory: 64m
  command: './run.sh'
  services:
  - vault-db
```

VaultをPWS上にデプロイしてみましょう。

```shell
$ cf push
```

デプロイが成功したらVaultの初期化の処理を行います。

```shell
$ export VAULT_ADDR="https://cf-vault-NAME.cfapps.io"
$ vault operator init -key-shares=2 -key-threshold=2
$ vault unseal <KEY1>
$ vault unseal <KEY2>
$ vault login <ROOT_TOKEN>
$ vault status
```

これでVaultの準備は完了です。

### Service BrokerをPWS上にデプロイ

Service BrokerをPWS上にデプロイします。Service Brokerの実態はGoで書かれているAPIベースのアプリケーションです。

```shell
$ git clone https://github.com/hashicorp/vault-service-broker
$ cd vault-service-broker
$ cf create-space vault-service-broker
$ cf target -s vault-service-broker
$ cf push --random-route --no-start
```

今回は便宜上PWS上にVault Service Brokerをデプロイしていますが、これはどこにデプロイされていても問題ありません。

次にデプロイしたService BrokerにVaultの設定を入れていきます。これを使ってService BrokerはVaultのトークンを生成します。

```shell
$ cf set-env vault-service-broker VAULT_ADDR <YOUR_VAULT_HTTPS_ADDR>
$ cf set-env vault-service-broker VAULT_TOKEN <YOUR_VAULT_TOKEN>
$ cf set-env vault-service-broker SECURITY_USER_NAME "vault"
$ cf set-env vault-service-broker SECURITY_USER_PASSWORD "broker-secret-password"
$ cf restage vault-service-broker
$ cf start vault-service-broker
```

アプリの確認をして、Service Brokerにアクセスしてみます。

```
$ export BROKER_URL=$(cf app vault-service-broker | grep -E -w 'urls:|routes:' | awk '{print $2}')
$ curl -s "${AUTH_USERNAME}:${AUTH_PASSWORD}@${BROKER_URL}/v2/catalog"
```

以下のようなレスポンスが返ってくるはずです。


<details><summary>レスポンス例</summary>

```json
{
  "services": [
    {
      "id": "0654695e-0760-a1d4-1cad-5dd87b75ed99",
      "name": "hashicorp-vault",
      "description": "HashiCorp Vault Service Broker",
      "bindable": true,
      "plan_updateable": false,
      "plans": [
        {
          "id": "0654695e-0760-a1d4-1cad-5dd87b75ed99.shared",
          "name": "shared",
          "description": "Secure access to Vault's storage and transit backends",
          "free": true,
          "metadata": {
            "displayName": "Architecture and Assumptions",
            "bullets": [
              "The Vault server is already running and is accessible by the broker.",
              "The Vault server may be used by other applications (it is not exclusively tied to Cloud Foundry).",
              "All instances of an application will share a token. This goes against the recommended Vault usage. This is a limitation of the Cloud Foundry service broker model.",
              "Any Vault operations performed outside of Cloud Foundry will require users to rebind their instances."
            ]
          }
        }
      ],
      "metadata": {
        "displayName": "Vault for PCF",
        "imageUrl": "data:image/gif;base64,iVBORw0KGgoAAAANSUhEUgAAAQAAAAEABAMAAACuXLVVAAAAJ1BMVEVHcEwVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUPAUIJAAAADHRSTlMAYOgXdQi7SS72ldNTKM7gAAAE00lEQVR42u3dvUscQRQA8JFzuSvlIJVpDBIhXGFlcZUYDFx3gmkskyIWV0iKpNjmqmvSpolsJwEPbEyjxTU5grD6/qgUfu3u7M7XvvcmgffKBZ0fem92dvbmPaUkJCQkJP7HSOovb7ON/67++psxEyC9qb8+2OAZfwZNALjiGH+YNQPyj/TjHwygGQD5PvX43QWYALBcox2/NwEzAG6mlON3RmADwC3ldNAHOwC+jwkT0AVAl4xDcAPAMc34h5krAH6SJaAjYLlPlYCOALg7QU/AOfgA8KeDPfAD5Ke4yZiCJwAA9d68A/4A+IQ3/lEWAoAzrPFXqr/ZEYB1b+4tIAwAv3ES8AKiApIRxAWsQ1zADOIChllcwOEAogK6C4gKKN6BYwCSOSABemEL5T5gAVaDFsop4AFgKyABc0yA/0L5MANUgO+9eWUAyIDlLkoChgO8Fso1d+D2AI+FcrIHFAA43W6fgK0ArgvlGVAB4Dr8DlyK41CAy3RgTkDjgt8B8GM/9A5ciMb9BweAdROrM7GOvzluA7AkY90SuBKGXHICmDex+tbxTT/uBjD8CV0S0PQHdAQ0f4iG1vHN87kroCkZO9YEtHyEnQF5/f+xYx3fksTOAAgD5LY1BTXgXMUF2KdxWoDDBjApYGMcF+D0ZEEIcHsJQQdwXE6SAVwX1FSAO20C7rIC9Am4+4sToE/AvcmSE3Be8+aAE3Bct2/CCLiqXbXxAfQJOAVOgD4B368auQD6Cvxh1coF2G16c8IFWGvauI0EeH5sjQMoPLZGART3rWIAesV9qwiA0qvjCIDKvhk/oPLmih3wBeICdiAy4KUABCAAAQhAAAIQgAA0wPva4AO4hgAEIAABCEAAAhCAAAQgAAEIQAACEIAA6PaIvtaGbNMJQAACEIAABCAAAfx7gOvIgKcTnpEAz99KjgMofCs5CuB2qqICSsdSIgDKx1L4AcsXKipg+VbFBVSPpXADtGMhzADtYLZezoMUcKmNr1cToATop4o/AydAPxbyDTgBxQn4PmoPU5MB9HOB9dUMqAD6ucCGciZEgFe71StN1RSIAPq5wAWwAqrRXE6FB2Co5sACaK6nxAMwlnPhABirSTAAzOVk6AGWahbkAFs1C2rAURYXsDqAqICVBYQBtKVDGKA7sY6/5Zi7QYDSucD6aK6mUJk9QwCduXV8UzWF8v0rAGCtp2WrZlC6g/sDknXr+LaKSMWajP4Aaz0vh1rKhVWkN8BeTih3qIo1CwbYywm51dNO0bbptDAUYyp+kkZUANfacI+18bAB7tXxHpIRGeBTH/D+gQIX4Fe9+ChDB3jWiNzBBlwrz0hxAf41vJM+JuDPtjdAdeZ4gJuA8ZXqTbEAbSvZtwVUNm75Aa27GbQEtO/n0A6A0NGiFQCjp0cbAEpXkxYAnEYO4QCkzjbBAKz+AcFFMNA6KKRhALyWMkk/BIDZRaPyyOn76hYhyk+tLgDsTiqlp1YHAH4vmeJTqx1A0U1n6AM4wx9fjWfuAJqOSs/JaANcKpp42kKyAOi6aj0moxlA2VfsIRmNgLupIoyDgQ1A3VtumJkB+ZkijpkZwNBfMDUBODosJqNmwKbiiM5FE4C0sV9xOvhQf/31lGd8lTTUqj1REhISEhISAfEXumiA5AUel8MAAAAASUVORK5CYII=",
        "longDescription": "The official HashiCorp Vault broker integration to the Open Service Broker API. This service broker provides support for secure secret storage and encryption-as-a-service to HashiCorp Vault.",
        "providerDisplayName": "HashiCorp",
        "documentationUrl": "https://www.vaultproject.io/",
        "supportUrl": "https://support.hashicorp.com/"
      }
    }
  ]
}
```
</details>

### Service BrokerでVaultのトークンを払い出す

それではこのService BrokerをCloud FoundryのMarketplaceに登録していきます。Marketplaceに登録することでユーザがオンデマンドでVaultのトークンを発行できるようになります。

アプリを一つデプロイし、そのアプリにVaultをBindしてトークンをセットします。

```shell
$ git clone https://github.com/tkaburagi/pcfdemoapp
$ cd pcfdemoapp
$ cf push pcfdemoapp-<NAME> -p pcfdemoapp/target/demo-1.0.0-BUILD-SNAPSHOT.jar
```

デプロイが成功したら準備は完了です。VaultをMarketplaceに登録します。

```shell
$ cf create-service-broker vault-service-broker "${AUTH_USERNAME}" "${AUTH_PASSWORD}" "https://${BROKER_URL}" --space-scoped
```

Marketplaceで確認をしてみます。

```console
$ cf marketplace
Getting services from marketplace in org kabu / space vault-sample as t.kaburagi@me.com...
OK

service             plans          description                                                                                                                      
hashicorp-vault    shared     HashiCorp Vault ServiceBroker
```

別の端末でVaultのログをTailしておきましょう。

```shell
$ cf logs cf-vault-kabu
```

それではService Brokerを使ってVaultトークンを払い出し、それをアプリケーションにセットしてみます。

```shell
$ cf create-service hashicorp-vault shared my-vault
```

少しすると`create`が成功するはずです。

```console
$ cf service my-vault
Showing info of service my-vault in org kabu / space vault-sample as t.kaburagi@me.com...

name:             my-vault
service:          hashicorp-vault
tags:
plan:             shared
description:      HashiCorp Vault Service Broker
documentation:    https://www.vaultproject.io/
dashboard:
service broker:   vault-broker-tkaburagi

Showing status of last operation from service my-vault...

status:    create succeeded
message:
started:   2019-08-22T09:52:16Z
updated:   2019-08-22T09:52:16Z
```

これをアプリにBindすることでアプリにVaultのトークンとそのトークンが扱うことのできるエンドポイントがセットされます。

```shell
$ cf bind-service pcfdemoapp-tkaburagi my-vault
```

Vaultのログを見ると以下のような出力がされ、Tokenが作られていることがわかります。

<details><summary>ログ出力例</summary>

```
2019-08-22T18:54:04.412+09:00 [RTR/10] [OUT] cf-vault-kabu.cfapps.io - [2019-08-22T09:54:04.399+0000] "PUT /v1/auth/token/roles/cf-7ecb3781-d8e2-4748-962d-fa798e921e95 HTTP/1.1" 204 95 0 "-" "Go-http-client/1.1" "10.10.2.116:20552" "10.10.149.220:61244" x_forwarded_for:"54.196.151.35, 10.10.2.116" x_forwarded_proto:"http" vcap_request_id:"c066efb4-d680-4ed9-6fb0-2e87d6b2f054" response_time:0.012431279 app_id:"35af1b55-e515-49af-b8e9-9b7677a92a86" app_index:"0" x_b3_traceid:"0b83426fd070343d" x_b3_spanid:"0b83426fd070343d" x_b3_parentspanid:"-" b3:"0b83426fd070343d-0b83426fd070343d"
2019-08-22T18:54:04.438+09:00 [RTR/10] [OUT] cf-vault-kabu.cfapps.io - [2019-08-22T09:54:04.420+0000] "POST /v1/auth/token/create/cf-7ecb3781-d8e2-4748-962d-fa798e921e95 HTTP/1.1" 200 278 595 "-" "Go-http-client/1.1" "10.10.2.116:20644" "10.10.149.220:61244" x_forwarded_for:"54.196.151.35, 10.10.2.116" x_forwarded_proto:"http" vcap_request_id:"dc2feda9-e048-4cfd-67f8-22f921d3d550" response_time:0.017286002 app_id:"35af1b55-e515-49af-b8e9-9b7677a92a86" app_index:"0" x_b3_traceid:"810b342767562f18" x_b3_spanid:"810b342767562f18" x_b3_parentspanid:"-" b3:"810b342767562f18-810b342767562f18"
```
</details>

アプリにセットされているVaultの設定を確認してみましょう。

```console
$ cf env pcfdemoapp-NAME
```

以下のようなJsonが返ってくるはずです。

<details><summary>cf env出力例</summary>

```json
System-Provided:
{
 "VCAP_SERVICES": {
  "hashicorp-vault": [
   {
    "binding_name": null,
    "credentials": {
     "address": "http://cf-vault-kabu.cfapps.io/",
     "auth": {
      "accessor": "YdCsRHVzsfdH0PYTR7CNQzLD",
      "token": "s.U3xkVk7jEdIJYnvCU4uXKxbP"
     },
     "backends": {
      "generic": [
       "cf/7ecb3781-d8e2-4748-962d-fa798e921e95/secret",
       "cf/4a153e07-fa28-4200-a696-22fae3915322/secret"
      ],
      "transit": [
       "cf/7ecb3781-d8e2-4748-962d-fa798e921e95/transit",
       "cf/4a153e07-fa28-4200-a696-22fae3915322/transit"
      ]
     },
     "backends_shared": {
      "application": "cf/4a153e07-fa28-4200-a696-22fae3915322/secret",
      "organization": "cf/513ca5eb-5710-42ba-98b9-279c26969cc7/secret",
      "space": "cf/dd4b66d4-3809-4060-9449-d8ea266dc56b/secret"
     }
    },
    "instance_name": "my-vault",
    "label": "hashicorp-vault",
    "name": "my-vault",
    "plan": "shared",
    "provider": null,
    "syslog_drain_url": null,
    "tags": [],
    "volume_mounts": []
   }
  ]
 }
}

{
 "VCAP_APPLICATION": {
  "application_id": "4a153e07-fa28-4200-a696-22fae3915322",
  "application_name": "pcfdemoapp-tkaburagi",
  "application_uris": [
   "pcfdemoapp-tkaburagi.cfapps.io"
  ],
  "application_version": "dd25918c-c073-4a55-8592-1c2b68c1100f",
  "cf_api": "https://api.run.pivotal.io",
  "limits": {
   "disk": 1024,
   "fds": 16384,
   "mem": 1024
  },
  "name": "pcfdemoapp-tkaburagi",
  "organization_id": "513ca5eb-5710-42ba-98b9-279c26969cc7",
  "organization_name": "kabu",
  "process_id": "4a153e07-fa28-4200-a696-22fae3915322",
  "process_type": "web",
  "space_id": "dd4b66d4-3809-4060-9449-d8ea266dc56b",
  "space_name": "vault-sample",
  "uris": [
   "pcfdemoapp-tkaburagi.cfapps.io"
  ],
  "users": null,
  "version": "dd25918c-c073-4a55-8592-1c2b68c1100f"
 }
}

No user-defined env variables have been set

No running env variables have been set

No staging env variables have been set
```
</details>

`hashicorp-vault`の欄がVaultに関する設定項目です。Vault APIのエンドポイント、払い出されたTokenやシークレットエンジンのエンドポイントがセットされています。

アプリからはこの環境変数を扱うことでVaultのシークレット機能を簡単に利用することができます。

### Vaultの中を確認する

最後にService Brokerによって生成されたVaultトークンでどのような設定がされているか確認してみましょう。

まずはトークンの確認です。`VAULT_APP_TOKEN`はcf envにセットされているトークンです。

```console
$ ROOT_TOKEN=<YOUR_ROOT_TOKEN>
$ VAULT_APP_TOKEN=<VAULT_APP_TOKEN>

$ VAULT_TOKEN=$ROOT_TOKEN vault token lookup $VAULT_APP_TOKEN
Key                  Value
---                  -----
accessor             YdCsRHVzsfdH0PYTR7CNQzLD
creation_time        1566467644
creation_ttl         120h
display_name         token-cf-bind-d46a4e2a-7c8d-4910-a12d-fbed99d73300
entity_id            n/a
expire_time          2019-08-27T09:54:08.185467731Z
explicit_max_ttl     0s
id                   s.U3xkVk7jEdIJYnvCU4uXKxbP
issue_time           2019-08-22T09:54:04.433243997Z
last_renewal         2019-08-22T09:54:08.185469741Z
last_renewal_time    1566467648
meta                 map[cf-binding-id:d46a4e2a-7c8d-4910-a12d-fbed99d73300 cf-instance-id:7ecb3781-d8e2-4748-962d-fa798e921e95]
num_uses             0
orphan               false
path                 auth/token/create/cf-7ecb3781-d8e2-4748-962d-fa798e921e95
policies             [cf-7ecb3781-d8e2-4748-962d-fa798e921e95 default]
renewable            true
role                 cf-7ecb3781-d8e2-4748-962d-fa798e921e95
ttl                  102h29m43s
type                 service
```

TTLやポリシーなどが設定されています。`policies`に`cf-7ecb3781-d8e2-4748-962d-fa798e921e95`がセットされていますが、これが`create-service`を実行した際にトークンと同時に作られるポリシーです。このポリシーを見てみます。

```console
$ VAULT_TOKEN=$ROO_TOKEN vault policy read "$(VAULT_TOKEN=$ROOT_TOKEN vault token lookup -format json $VAULT_APP_TOKEN | jq -r '.data.policies[0]')"
path "cf/7ecb3781-d8e2-4748-962d-fa798e921e95" {
  capabilities = ["list"]
}

path "cf/7ecb3781-d8e2-4748-962d-fa798e921e95/*" {
	capabilities = ["create", "read", "update", "delete", "list"]
}

path "cf/dd4b66d4-3809-4060-9449-d8ea266dc56b" {
  capabilities = ["list"]
}

path "cf/dd4b66d4-3809-4060-9449-d8ea266dc56b/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "cf/513ca5eb-5710-42ba-98b9-279c26969cc7" {
  capabilities = ["list"]
}

path "cf/513ca5eb-5710-42ba-98b9-279c26969cc7/*" {
  capabilities = ["read", "list"]
}

path "cf/4a153e07-fa28-4200-a696-22fae3915322" {
  capabilities = ["list"]
}

path "cf/4a153e07-fa28-4200-a696-22fae3915322/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

エンドポイントへの権限がいくつか付与されていることがわかります。では、最後にこのエンドポイントが何を確認するため以下のコマンドを事項します。

```console
$ VAULT_TOKEN=$ROOT_TOKEN vault secrets list | grep cf                                                                         
cf/4a153e07-fa28-4200-a696-22fae3915322/secret/     generic      generic_6804f63f      n/a
cf/4a153e07-fa28-4200-a696-22fae3915322/transit/    transit      transit_da343bb3      n/a
cf/513ca5eb-5710-42ba-98b9-279c26969cc7/secret/     generic      generic_b55762b7      n/a
cf/6914821a-29f6-442e-90e0-41860fe89895/secret/     generic      generic_053110c5      n/a
cf/6914821a-29f6-442e-90e0-41860fe89895/transit/    transit      transit_0430517b      n/a
cf/7ecb3781-d8e2-4748-962d-fa798e921e95/secret/     generic      generic_42a4f09b      n/a
cf/7ecb3781-d8e2-4748-962d-fa798e921e95/transit/    transit      transit_e5a000b0      n/a
cf/broker/                                          generic      generic_81c6135e      n/a
cf/dd4b66d4-3809-4060-9449-d8ea266dc56b/secret/     generic      generic_c14141c8      n/a
```

アプリの環境変数にセットされている通り、それぞれ`generic`と`transit`のシークレットエンジンを扱うことができます。

## PCF Auth Methodを利用する(WIP)

Vault1.2から利用可能となったPCF Auth Methodを利用します。これを利用するとVaultのトークンをPCFのインタスタンスが自動的に取得できるようになります。これはPCFの`Container Identity Assurance`を利用したものです。詳細は[こちら](https://content.pivotal.io/blog/new-in-pcf-2-1-app-container-identity-assurance-via-automatic-cert-rotation)を見てください。

cf dev bosh env
export BOSH_GW_HOST="10.144.0.2";
export BOSH_GW_USER="jumpbox";
export BOSH_ENVIRONMENT="10.144.0.2";
export BOSH_CLIENT="ops_manager";
export BOSH_CLIENT_SECRET="DYCMS_0WK5c4cOVptqO1B500r3noEZsC";
export BOSH_CA_CERT="/Users/kabu/.cfdev/state/bosh/ca.crt";
export BOSH_GW_PRIVATE_KEY="/Users/kabu/.cfdev/state/bosh/jumpbox.key";

vault auth enable pcf

vault write auth/pcf/config \
      identity_ca_certificates=@/Users/kabu/.cfdev/state/bosh/ca.crt \
      pcf_api_addr=https://api.dev.cfdev.sh \
      pcf_username=vault \
      pcf_password=pa55w0rd \
      pcf_api_trusted_certificates=@/Users/kabu/cloudfoundry/pcfapi.crt

 vault write auth/pcf/roles/my-role \
    bound_space_ids=$(cf space cfdev-space --guid) \
    bound_organization_ids=$(cf org cfdev-org --guid) \
    policies=default


## 参考リンク

* [Pivotal Web Services](https://run.pivotal.io/)
* [Vault Service Broker]https://github.com/hashicorp/vault-service-broker)
* [Vault CF Plugin](https://github.com/hashicorp/vault-plugin-auth-cf)
* [Vault PCF Auth Method](https://www.vaultproject.io/docs/auth/pcf.html)
* [Vault PCF Auth Method API](https://www.vaultproject.io/api/auth/pcf/index.html)

