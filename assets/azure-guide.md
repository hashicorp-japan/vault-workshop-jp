# Azure 環境のセットアップ

## Azure アカウントの作成

[https://signup.azure.com/signup](https://signup.azure.com/signup)

## Subscription の作成
ある場合は飛ばして OK

* [Azure Portal](https://portal.azure.com/#home)にログイン
* `Subscriptions`を検索
* `Subscriptions`画面で`+ Add`
* `Pay-As-You-Go` (未使用の場合は`Free Trial`でも OK)
* `No technical support`をチェック
* その他は普通に入力

これで作成完了。生成された`Subscription ID`をメモ。

## Tenant ID の取得

* [Azure Portal](https://portal.azure.com/#home)にログイン
* `Azure Active Directory`を検索
* `Azure Active Directory`画面で左カラムから`Properties`を選択
* `Default Directory`の`Directry ID`をメモ

これが`Tenant ID`。

## App Regitrations

* `Azure Active Directory`画面で左カラムから`App registrations`を選択
* `+ New Regiter`
* `Name`に`vault-app`を入力して`Register`
* 完了したら`Application ID`をメモ

これが`Client ID`。

## Client Secret 取得

* App 画面の左カラムから`Certificates & secrets`
* `+New client secret` -> `ADD`
* 生成された`Value`列をコピー

これが`Client Secret`。

## 権限の設定

* App 画面の左カラムから`API permissions`
* `+ Add a permission`
* 下の方にスクロールし、`Azure Active Directory Graph`
* `Delegated permissions` -> `User` -> `User.Read`
* `Application permissions` -> `Application` -> `Application.ReadWrite.All`
* `Application permissions` -> `Directory` -> `Directory.ReadWrite.All`
* `API permissions`画面に戻り、`Grant admin consent for azure`

これで権限の設定は完了。

## ロールアサイメント

* [こちら](https://portal.azure.com/#blade/Microsoft_Azure_Billing/SubscriptionsBlade)から先ほど作った Subsciption を選択
* `Subsciption`画面の左カラムから`Access control (IAM)`
* 右カラムの`Add a role assignment` -> `Add`
* `Role`で`Owner`を選択
* `Select`で`vault-app`と検索し選択
* `Save`

## Resource Group 作成

* [Azure Portal](https://portal.azure.com/#home)にログイン
* `Resource groups`を検索
* `Resource groups`画面で`+Add`
* `Resource group`に`vault-resource-group`を入力
* `Region`で`(Asia Pacific) Japan East`を選択
* `Review + create`
* `create`


これで準備は完了です。

* `Subscription ID`
* `Tenant ID`
* `Client ID`
* `Client Secret`

が手元にあることを確認して下さい。
