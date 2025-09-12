# Token について

Token は Vault とやり取りする上でコアとなるものです。つまり、Token がなければ Vault とやり取りすることはできません。

この Token をいかに取得するか、というメカニズムを提供するのが Auth Method になります。
Token は通常は次のようなテキスト形式で表されます。

`s.RmHqNz3ssJMOBZsU1ldBMCi3`

Token には様々な種類のタイプや特徴がありますので、いくつか紹介していきます。

## Root token

Root token は Vault が初期化されたときに作成される特別な Token です。
また、他の Token と違い、TTL が無期限であることも特徴です。

Root という名前が示すとおり、Vault 上のどのオペレーションも行なうことができます。よって、Root Token は管理者により Vault の最初の設定のときにだけ使用し、あらかたの設定が終わったら破棄してください。再度 Root Token が必要になった際は、再作成することを推奨します。[Root Token の再作成方法はこちら](https://learn.hashicorp.com/vault/operations/ops-generate-root)

## 他の Token

Root Token の他に Vault には以下の２種類の Token のタイプがあります。

1. Service token
2. Batch token

Service Token は Vault が開発された時から存在しているもので、今もほとんどのユーザーが利用しています。また、Token に関する全ての機能（Renewal, Revokation, Child token の作成など）が使えます。ただ、その多機能ぶりと同時に処理は少々重くなります。

Batch Token は Vault 1.0 からサポートされた新しいタイプの Token です。軽量版 Service Token とも言えるもので、少量の情報だけを保持している Token になります。特徴としては、Token は全てインメモリに保存されます。よって、Vault がダウンすると Batch Token は全て失われてしまいます。その代わり非常に軽量なので、大量の Request への対応やスケーラビリティに向いています。

以下か大まかな違いのリストです。使われている用語については追々学んでいくので今はそこまで気にしないでください。

機能  | Service Token  |  Batch Token
--|---|--
Root token として使えるか？  | Yes  |  No
Child token を作れるか？  |  Yes |  No
Renew できるか？  |  Yes |  No
Max TTL が設定できるか？  |  Yes |  No
Periodic の設定ができるか？  |  Yes |  No
Accessor を持てるか？  | Yes  |  No
Cubbyhole を持てるか？  |  Yes |  No
Parent が Revoke されたら | Revoke される | 動かなくなる
動的 Secret のリースの管理  | 自分自身  | Parent
Performance Replication で使えるか？  | No  | Yes
Performance stand-by node で使えるか？  | No  |  Yes
コスト  | ヘビー  |  ライト

### Service token

Service Token は階層構造で構成されます。
つまり、各 Token は Child Token を作成することで、Parent Token となります（もちろん Token を作成できるポリシーが必須）。Parent Token が Revoke されると、全ての Child token と付随している Lease は Revoke されます。
ただし、Orphan token は Parent なしで、自らの TTL で存在できます。

Service token には様々な機能があります。非常に豊富なので、ここでは良く使われるものを見ていきます。

>**注意**　Auth method によって設定できないものもあります。詳細は各 Auth method のドキュメントを参照ください。

#### 様々な Service token

Token  | 内容 | 作成方法
--|---|---
通常の Token  | MaxTTL の期間内なら何回でも Renew することができる | `vault  token create` | あり  | あり | できる | なし
Orphan  |  挙動は通常の Token とほぼ同じだが、Parent token がいない | `vault token create -orphan`
Periodic Token  | MaxTTL が設定されないので、Period 期間内に Renew すれば延々と利用できる | `vault token create -period`
Counting Token  | 利用できる回数に制限をもたせる　| `vault token create -use-limit`

上記に列挙したもの以外でも、Service token は Option が豊富にあり、それらを組み合わせることで用途に合わせた Token を作成できます。使用できる Option などは[API ドキュメント](https://www.vaultproject.io/api/auth/token/index.html)を参照ください。


## まとめ

Token は Vault とやり取りをするために必須のものです。また用途に合わせて挙動を設定できます。Token のライフサイクルを理解することで、より安全に Secret の管理・運用が可能になります。

Token は、 `vault token create`などで静的なものを作成し、Client へ配布する方法もありますが、各 Auth method で認証して動的に作成・配布する手段が推奨されます。

Auth method によって、設定できる Option が違ったりもするので、そのあたりは各ドキュメントを参照いただければと思います。
