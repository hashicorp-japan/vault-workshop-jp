# HashiCorp Vault Workshop

[Vault](https://www.vaultproject.io/)はHashiCorpが中心に開発をするOSSのシークレット管理ツールです。Vaultを利用することで既存のStaticなシークレット管理のみならず、クラウド、データベースやSSHなどの様々なシークレットを動的に発行することができます。Vaultはマルチプラットフォームでかつ全ての機能をHTTP APIで提供しているため、環境やクライアントを問わず利用することができます。

本ワークショップはOSSの機能を中心に様々なユースケースに合わせたハンズオンを用意しています。

## Pre-requisite

* 環境
	* macOS or Linux

* ソフトウェア
	* Vault
	* Docker
	* MySQLクライアント
	* Java 12(いつか直します...)
	* jq, watch, wget, curl
	* vagrant(SSHの章のみ必要)
	* minikube(Kubernetesの章のみ必要)
	* helm(Kubernetesの章のみ必要)

* アカウント
	* GitHub
	* AWS / Azure / GCP

## 資料

* [Vault Overview](https://docs.google.com/presentation/d/14YmrOLYirdWbDg5AwhuIEqJSrYoroQUQ8ETd6qwxe6M/edit?usp=sharing)

## お勧めの進め方

初めてVaultを扱う人は下記の順番で消化すると一通りのVaultの使い方が掴めるためお勧めです。

1. 初めてのVault
2. Databases Secret Engine
3. 認証とポリシー & トークン
4. Auth Methodのいずれか
5. Public Clouds Secret Engineのいずれか
6. Transit

## アジェンダ
* [初めてのVault](contents/hello-vault.md)
* [Secret Engine 1: Key Value](contents/kv.md)
* [Secret Engine 2: Databases](contents/db.md)
* [認証とポリシー](contents/policy.md)
	* [ポリシーエクササイズ](contents/policy_ex.md) 
* [トークン](contents/token.md)
* [Auth Method 1: LDAP](contents/auth_ldap.md)
* [Auth Method 2: AppRole](contents/approle.md)
* [Auth Method 3: OIDC](https://learn.hashicorp.com/vault/operations/oidc-auth)
* [Auth Method 4: GitHub](https://learn.hashicorp.com/vault/getting-started/authentication)
* [Auth Method 5: AWS](contents/auth_aws.md)
* [Auth Method 6: Kubernetes](contents/k8s.md)
* [Response Rapping](contents/response-wrapping.md)
* Secret Engine 3: Public Cloud ([AWS](contents/aws.md), [Azure](contents/azure.md), [GCP](contents/gcp.md))
* [Secret Engine 4: PKI Engine](contents/pki.md)
* [Secret Engine 5: Transit (Encryption as a Service)](contents/transit.md)
* [Secret Engine 6: SSH](contents/ssh.md)
* [Secret Engine 7: Transform(Tokenization)](contents/transformation.md)
* [HashiCorp Nomadとの連携機能](https://github.com/hashicorp-japan/nomad-workshop/blob/master/contents/nomad-vault.md)
* [Enterprise機能の紹介](https://docs.google.com/presentation/d/1dtoRmLxySDL8PTEe_X51BQNIXn19H_910StO2DlFkLI/edit?usp=sharing)
