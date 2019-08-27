# Response Wrappingを使ってシークレットをセキュアに渡して取得する。

Vaultから生成されたシークレットを利用する際、シークレットの受け渡しは非常にセンシティブな作業です。その際`Cubbyhole Response Wrapping`という機能を利用し、トークンを一回限りのトークンでラップして受け渡すような運用が可能です。

その際重要になってくる`Cubbyhole`というシークレットエンジンをまずは使ってみたいと思います。

## Cubbyhole

`Cubbyhole`はロッカーや安全な場所という意味で、このシークレットエンジンは他とは違いVaultのトークンに必ず一つ割り当てられ、そのバックエンドは他のいかなる強力な権限を持つトークンからも見ることができません。ルートトークンからも他のCubbyholeは見ることができません。また、Cubbyholeに格納されたデータはトークンのTTLが切れたり、Revokeされると同時に消滅します。

まずは試してみましょう。

TTLが15分のトークンを作ってみます。前の手順で作った`my-first-policy.hcl`を以下のように変更してwriteしてトークンを作ります。

```hcl
path "database/roles/+" {
  capabilities = ["list","create", "read"]
}

path "database/roles/role-handson" {
  capabilities = ["deny"]
}

path "sys/*" {
  capabilities = ["read", "list"]
}
```

```console
$ vault policy write my-policy path/to/my-first-policy.hcl
$ vault token create -policy=my-policy -ttl=15m

Key                  Value
---                  -----
token                s.vz9bwNR7LRtTYiTqo3KxO9aV
token_accessor       FRotEsEBaUxvB0xV84P4vhnH
token_duration       5m
token_renewable      true
token_policies       ["default" "my-policy"]
identity_policies    []
policies             ["default" "my-policy"]
```

このトークンを使って`cubbyhole`にデータを投入します。

```console
$ VAULT_TOKEN=<TOKEN_ABOVE> vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_e3aa0798    per-token private secret storage
database/     database     database_603dc42e     n/a
identity/     identity     identity_86c0240d     identity store
kv/           kv           kv_20084de2           n/a
sys/          system       system_ae51ee57       system endpoints used for control, policy and debugging
transit/      transit      transit_ec14846c      n/a

$ VAULT_TOKEN=s.vz9bwNR7LRtTYiTqo3KxO9aV vault write cubbyhole/my-cubbyhole-secret foo=bar

$ VAULT_TOKEN=s.vz9bwNR7LRtTYiTqo3KxO9aV vault read cubbyhole/my-cubbyhole-secret
Key    Value
---    -----
foo    bar
```

次にルートトークンからこのデータを参照してみましょう。

```console
$ export ROOT_TOKEN=<YOUR_ROOT_TOKEN>
$ VAULT_TOKEN=$ROOT_TOKEN vault list cubbyhole/

$ VAULT_TOKEN=$ROOT_TOKEN vault read cubbyhole/my-cubbyhole-secret 
No value found at cubbyhole/my-cubbyhole-secret
```

データは参照できません。15分後ログインしようとするとアクセスできずcubbyhole内のデータも抹消されます。

以上がCubbyholeです。`Response Wrapping`は内部的にCubbyholeを使ってセキュアなクレデンシャルの受け渡しを実現します。

## Response Wrappingのワークフロー

Response Wrappingのワークフローは少し複雑です。

1. 実際に利用するクレデンシャルを発行する際に、一時トークン(Wrapping Token)を同時発行します。
2. クレデンシャルはWrapping Tokenの`cubbyhole/response`内に保存されます。
3. クライアントはWapping Tokenを使って`unwrap`という処理を行い、`cubbyhole/response`内のクレデンシャルを取り出します。
4. 一度利用された`Wrappgin Token`は即座に無効化され2度とクレデンシャルは取得できなくなります。

このような感じです。試してみましょう。ゆっくりやって欲しいのでTTLは長めの1時間にします。まずクレデンシャルの発行です。クレデンシャルはVaultから発行できるシークレットであればなんでもOKです。

ここでは先ほど使ったAppRoleのシークレットIDを発行してみましょう。まず通常だとこのような結果になります。

```console
$ vault write -f auth/approle/role/my-approle/secret-id
Key                   Value
---                   -----
secret_id             f2f32284-5f39-8347-9278-1b879acedd98
secret_id_accessor    d61156ac-f797-ab7e-5024-a95584f78458
```

次は`-wrap-ttl`のオプションを使ってラッピングトークンを発行します。

```console
$ vault write -wrap-ttl=1h  -f auth/approle/role/my-approle/secret-id
Key                              Value
---                              -----
wrapping_token:                  s.3OzsP31vNPiqoksrtqY0nSmV
wrapping_accessor:               hiw2JzGYV7yKVE4TchiBBwUd
wrapping_token_ttl:              1h
wrapping_token_creation_time:    2019-07-17 21:43:50.763833 +0900 JST
wrapping_token_creation_path:    auth/approle/role/my-approle/secret-id
```

このラッピングトークンは1時間有効ですが、一度使うと抹消されます。`unwrap`という操作がアンラップし、Secret IDを取り出してみましょう。

```console
$ vault unwrap <WRAPPING_TOKEN>
Key                   Value
---                   -----
secret_id             eb757e5e-fe36-44c6-7b68-f0e19c692a27
secret_id_accessor    ffe9a83b-9dec-fd86-3d9d-085390d98776
```

Secret IDを取得できました。もう一度unwrapしてみます。

```console
$ vault unwrap <WRAPPING_TOKEN>
Error unwrapping: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/sys/wrapping/unwrap
Code: 400. Errors:

* wrapping token is not valid or does not exist

$ vault token lookup <WRAPPING_TOKEN>
Error looking up token: Error making API request.

URL: POST http://127.0.0.1:8200/v1/auth/token/lookup
Code: 403. Errors:

* bad token
```

unwrapもできず、トークンをLookupしてもエラーが返りトークンが無効になっていることがわかります。このようにTTL内でも一度利用され、クレデンシャルが取得されると2度と利用できません。

余裕のある方はもう一度同じ手順でラッピングトークンを作り、今度はそのトークンの`cubbyhole/response`にアクセスしてトークンが保存されていることを確認しましょう。

```console
$ vault write -wrap-ttl=1h  -f auth/approle/role/my-approle/secret-id
$ VAULT_TOKEN=<WRAPPING_TOKEN> vault read cubbyhole/response -format=json
{
  "request_id": "e09bbe6e-d0de-4270-c386-471ce95f9d67",
  "lease_id": "",
  "lease_duration": 0,
  "renewable": false,
  "data": {
    "response": "{\"request_id\":\"b461f7d7-aec4-5543-735a-62118084c69f\",\"lease_id\":\"\",\"renewable\":false,\"lease_duration\":0,\"data\":{\"secret_id\":\"1a532c44-8d7c-84ee-ce3a-4e743a717a42\",\"secret_id_accessor\":\"0479662c-1b5c-fde1-3214-3c645baffe7c\"},\"wrap_info\":null,\"warnings\":null,\"auth\":null}"
  },
  "warnings": [
    "Reading from 'cubbyhole/response' is deprecated. Please use sys/wrapping/unwrap to unwrap responses, as it provides additional security checks and other benefits."
  ]
}
```

JSONのレスポンスでラッピングトークンの`cubbyhole/response`内に`secret_id`が格納されていることがわかります。`read`を行っても`unwrap`と同様、ラッピングトークンが無効になります。

```console
$ vault token lookup <WRAPPING_TOKEN>
Error looking up token: Error making API request.

URL: POST http://127.0.0.1:8200/v1/auth/token/lookup
Code: 403. Errors:

* bad token
```

`Response Wrapping`はAppRole以外にもトークンなど様々なシークレットに利用することができます。これを利用することでアプリなどからシークレットを取得する際も特権ユーザのトークンを記述したり、Secret IDを直で記述することなくセキュアにシークレットを取り出すことができます。また、人にシークレットを渡す際もWrapping Tokenのみを渡して取得してもらうことでより安全なシークレット管理が可能になります。

## 参考リンク
* [Cubbyhole Secret Engine](https://www.vaultproject.io/docs/secrets/cubbyhole/index.html)
* [Cubbyhole API Document](https://www.vaultproject.io/api/secret/cubbyhole/index.html)
* [Response Wrapping](https://www.vaultproject.io/docs/concepts/response-wrapping.html)