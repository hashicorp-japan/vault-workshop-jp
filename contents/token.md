# Tokenについて

TokenはVaultとやり取りする上でコアとなるものです。つまり、TokenがなければVaultとやり取りすることはできません。

このTokenをいかに取得するか、というメカニズムを提供するのがAuth Methodになります。
Tokenは通常は次のようなテキスト形式で表されます。

`s.RmHqNz3ssJMOBZsU1ldBMCi3`

Tokenには様々な種類のタイプや特徴がありますので、いくつか紹介していきます。

## Root token

Root tokenはVaultが初期化されたときに作成される特別なTokenです。
また、他のTokenと違い、TTLが無期限であることも特徴です。

Rootという名前が示すとおり、Vault上のどのオペレーションも行なうことができます。よって、Root Tokenは管理者によりVaultの最初の設定のときにだけ使用し、あらかたの設定が終わったら破棄してください。再度Root Tokenが必要になった際は、再作成することを推奨します。[Root Tokenの再作成方法はこちら](https://learn.hashicorp.com/vault/operations/ops-generate-root)

## 他のToken

Root Tokenの他にVaultには以下の２種類のTokenのタイプがあります。

1. Service token
2. Batch token

Service TokenはVaultが開発された時から存在しているもので、今もほとんどのユーザーが利用しています。また、Tokenに関する全ての機能（Renewal, Revokation, Child tokenの作成など）が使えます。ただ、その多機能ぶりと同時に処理は少々重くなります。

Batch TokenはVault 1.0からサポートされた新しいタイプのTokenです。軽量版Service Tokenとも言えるもので、少量の情報だけを保持しているTokenになります。特徴としては、Tokenは全てインメモリに保存されます。よって、VaultがダウンするとBatch Tokenは全て失われてしまいます。その代わり非常に軽量なので、大量のRequestへの対応やスケーラビリティに向いています。

以下か大まかな違いのリストです。使われている用語については追々学んでいくので今はそこまで気にしないでください。

機能  | Service Token  |  Batch Token
--|---|--
Root tokenとして使えるか？  | Yes  |  No
Child tokenを作れるか？  |  Yes |  No
Renewできるか？  |  Yes |  No
Max TTLが設定できるか？  |  Yes |  No
Periodicの設定ができるか？  |  Yes |  No
Accessorを持てるか？  | Yes  |  No
Cubbyholeを持てるか？  |  Yes |  No
ParentがRevokeされたら | Revokeされる | 動かなくなる
動的Secretのリースの管理  | 自分自身  | Parent
Performance Replicationで使えるか？  | No  | Yes
Performance stand-by nodeで使えるか？  | No  |  Yes
コスト  | ヘビー  |  ライト

### Service token

Service Tokenは階層構造で構成されます。
つまり、各TokenはChild Tokenを作成することで、Parent Tokenとなります（もちろんTokenを作成できるポリシーが必須）。Parent TokenがRevokeされると、全てのChild tokenと付随しているLeaseはRevokeされます。
ただし、Orpan tokenはParentなしで、自らのTTLで存在できます。

Service tokenには様々な機能があります。非常に豊富なので、ここでは良く使われるものを見ていきます。

>**注意**　Auth methodによって設定できないものもあります。詳細は各Auth methodのドキュメントを参照ください。

#### 様々なService token

Token  | 内容 | 作成方法
--|---|---
通常のToken  | MaxTTLの期間内なら何回でもRenewすることができる | `vault  token create` | あり  | あり | できる | なし
Orphan  |  挙動は通常のTokenとほぼ同じだが、Parent tokenがいない | `vault token create -orphan`
Periodic Token  | MaxTTLが設定されないので、Period期間内にRenewすれば延々と利用できる | `vault token create -period`
Counting Token  | 利用できる回数に制限をもたせる　| `vault token create -use-limit`

上記に列挙したもの以外でも、Service tokenはOptionが豊富にあり、それらを組み合わせることで用途に合わせたTokenを作成できます。使用できるOptionなどは[APIドキュメント](https://www.vaultproject.io/api/auth/token/index.html)を参照ください。


## まとめ

TokenはVaultとやり取りをするために必須のものです。また用途に合わせて挙動を設定できます。Tokenのライフサイクルを理解することで、より安全にSecretの管理・運用が可能になります。

Tokenは、 `vault token create`などで静的なものを作成し、Clientへ配布する方法もありますが、各Auth methodで認証して動的に作成・配布する手段が推奨されます。

Auth methodによって、設定できるOptionが違ったりもするので、そのあたりは各ドキュメントを参照いただければと思います。
