# HashiCorp Vault Workshop

[Vault](https://www.vaultproject.io/) は HashiCorp が中心に開発をする OSS のシークレット管理ツールです。Vault を利用することで既存の Static なシークレット管理のみならず、クラウド、データベースや SSH などの様々なシークレットを動的に発行することができます。Vault はマルチプラットフォームでかつ全ての機能を HTTP API で提供しているため、環境やクライアントを問わず利用することができます。

本ワークショップは OSS の機能を中心に様々なユースケースに合わせたハンズオンを用意しています。

## Pre-requisite

* 環境
	* macOS or Linux(Ubuntu 推奨)

* ソフトウェア
	* Vault
	* Docker
	* MySQL クライアント
	* Java 12(いつか直します...)
	* jq, watch, wget, curl
	* vagrant(SSH の章のみ必要)
	* minikube(Kubernetes の章のみ必要)
	* helm(Kubernetes の章のみ必要)

* アカウント
	* GitHub
	* AWS / Azure / GCP

## Vault 概要の学習

* こちらのビデオをご覧ください。

[HashiCorp Vault で始めるクラウドセキュリティ対策](https://www.youtube.com/watch?v=PJaNVSEXcUA&t=1s)

## 資料

* [Vault Overview](https://docs.google.com/presentation/d/14YmrOLYirdWbDg5AwhuIEqJSrYoroQUQ8ETd6qwxe6M/edit?usp=sharing)

## お勧めの進め方

初めて Vault を扱う人は下記の順番で消化すると一通りの Vault の使い方が掴めるためお勧めです。

1. 初めての Vault
2. Databases Secret Engine
3. 認証とポリシー & トークン
4. Auth Method のいずれか
5. Public Clouds Secret Engine のいずれか
6. Transit

## アジェンダ
* [初めての Vault](contents/hello-vault.md)
* [Secret Engine 1: Key Value](contents/kv.md)
* [Secret Engine 2: Databases](contents/db.md)
* [認証とポリシー](contents/policy.md)
	* [ポリシーエクササイズ](contents/policy_ex.md)
* [トークン](contents/token.md)
* [Auth Method 1: LDAP](contents/auth_ldap.md)
* [Auth Method 2: AppRole](contents/approle.md)
* [Auth Method 3: OIDC](https://learn.hashicorp.com/vault/operations/oidc-auth)
* [Auth Method 4: GitHub](https://learn.hashicorp.com/vault/getting-started/authentication)
* Auth Method 5: Public Cloud ([AWS](contents/auth_aws.md), Azure, [GCP](contents/gcp-auth.md))
* [Auth Method 6: Kubernetes](contents/k8s.md)
* [Auth Method 7: MFA (Enterprise)](contents/mfa.md)
* Secret Engine 3: Public Cloud ([AWS](contents/aws.md), [Azure](contents/azure.md), [GCP](contents/gcp.md))
* [Secret Engine 4: PKI Engine](contents/pki.md)
* [Secret Engine 5: Transit (Encryption as a Service)](contents/transit.md)
* [Secret Engine 6: SSH](contents/ssh.md)
* [Secret Engine 7: Transform / Tokenization (Enterprise)](contents/transformation.md)
* [Response Wrapping](contents/response-wrapping.md)
* [HashiCorp Nomad との連携機能](https://github.com/hashicorp-japan/nomad-workshop/blob/master/contents/nomad-vault.md)
* [Enterprise 機能の紹介](https://docs.google.com/presentation/d/1dtoRmLxySDL8PTEe_X51BQNIXn19H_910StO2DlFkLI/edit?usp=sharing)
* [Vault Ops Workshop](https://docs.google.com/document/d/1KWl3Krv3L4A0UQmw5deanXHGKr5Mu8kKoTMGNEyAgTM/edit#heading=h.wr5wzikn620)
