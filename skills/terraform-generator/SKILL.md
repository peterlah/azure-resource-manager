---
description: Azure 아키텍처 사양(또는 자연어 요구사항)을 Terraform IaC 모듈로 변환합니다. Azure Verified Modules(AVM) 우선, Managed Identity 기반 인증, Key Vault 시크릿 참조, 명시적 backend, 검증된 변수/출력을 포함합니다. 사용자가 "Terraform 짜줘", "tf 코드 만들어줘", "IaC를 Terraform으로", "azurerm 모듈" 등을 요청하거나 architecture-interview 스킬의 ADR을 IaC로 변환할 때 사용
---

# Azure Terraform Generator

자연어 요구사항 또는 `architecture-interview` 스킬의 ADR을 검증된 Terraform 모듈로 변환합니다. 기본 동작은 **파일 생성 + `terraform validate`**이며, 실제 `apply`는 사용자의 명시적 요청 시에만 수행합니다.

## 사용 시점
- ADR(`./diagrams/<adr-id>.md`) → Terraform 모듈 변환
- "AKS + ACR + Key Vault 묶은 Terraform 짜줘"
- "이 Bicep을 Terraform으로 옮겨줘"
- 신규 환경 IaC 부트스트랩

`bicep-generator` 와의 차이:
- **Bicep** — Azure 전용, 1st-class 지원, ARM 직접 변환
- **Terraform** — 멀티 클라우드 표준, 더 큰 모듈 생태계, 더 강한 state 관리, AVM(Azure Verified Modules) 활용

`architecture-interview`의 ADR이 있으면 거기서 시작하면 가장 정확. 없으면 직접 인터뷰부터.

## ⚠️ 안전 원칙

### 인증: Managed Identity 우선
- 코드에서 사용하는 Azure 인증은 항상 Managed Identity 또는 Workload Identity 우선
- 키/시크릿 인증은 **legacy로 명시**하고 사용 자제
- `provider "azurerm"`은 CLI 인증 또는 SP(CI/CD)만, 평문 자격증명 절대 코드 X

### 시크릿: Key Vault 데이터 소스
- 패스워드·연결 문자열·API 키는 **반드시** `data "azurerm_key_vault_secret"` 으로 참조
- 파라미터 기본값에 **시크릿 절대 X** — `<YOUR-SECRET-HERE>` 같은 명시적 placeholder만
- `terraform.tfvars` 는 `.gitignore` 권장 안내

### Backend: 명시적 원격 state
- `backend "azurerm"` 으로 Storage Account 사용
- 사용자에게 backend 리소스가 **선행 부트스트랩** 됐는지 확인 (없으면 별도 1회성 스크립트 안내)
- state 파일이 시크릿을 포함할 수 있음 → SAS 또는 Managed Identity 권한으로 접근 제한

### 배포 전 필수 검증
1. `terraform fmt -check` — 스타일 통일
2. `terraform validate` — 문법·참조 검증
3. `terraform plan -out=tfplan` — 변경 프리뷰
4. 사용자 승인 후에만 `terraform apply tfplan`

### Azure Best Practices 준수
- `azurerm` 최소 버전 **4.2** 이상 (latest 권장)
- 공식 문서: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- 스타일 가이드: https://developer.hashicorp.com/terraform/language/style

## 워크플로우

### 1단계: 입력 정리

다음 중 하나로 시작:

**(a) ADR이 이미 있는 경우 (권장)**
- `architecture-interview` 가 만든 `./diagrams/<adr-id>.md` 읽기
- 컴포넌트 표·SKU·리전·태그·네트워크 토폴로지 추출
- 누락된 항목만 사용자에게 추가 질문

**(b) ADR 없이 직접 시작**
- 핵심 정보 수집 (resource group / 리전 / 리소스 타입 + SKU / 네트워크 / 태그)
- 누락 항목은 명시적 질문, 추측 금지

```
## 📋 Terraform 생성 입력

- **모듈명**: order-platform
- **리소스 그룹**: rg-order-prod
- **리전**: koreacentral
- **DR 리전**: japaneast (해당 시)
- **Backend**: 기존 사용 / 신규 생성
- **포함 리소스**: AKS, ACR, Key Vault, Azure SQL, Redis, Front Door
- **AVM 사용**: ✅ (가능한 경우 우선)
- **태그**: env=prod, owner=peterlah, cost-center=eng
```

### 2단계: 모듈 구조 결정

**파일 레이아웃 원칙**

```
terraform/
├── main.tf              # 루트 모듈 — module 호출 + 리소스 그룹
├── variables.tf         # 입력 변수
├── outputs.tf           # 출력
├── versions.tf          # provider/terraform 버전 고정
├── backend.tf           # remote state
├── locals.tf            # 계산된 값·태그·네이밍
├── terraform.tfvars     # 환경별 값 (gitignore 권장)
├── modules/
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── data/            # SQL, Redis, Storage
│   ├── compute/         # AKS, ACR
│   └── identity/        # Key Vault, Managed Identities
└── environments/
    ├── dev.tfvars
    ├── stg.tfvars
    └── prod.tfvars
```

**모듈화 판단 기준**:
- 3개 이상 리소스가 묶이면 → 모듈 분리
- 환경별로 값만 다르면 → 모듈 + tfvars
- 단일 리소스라면 → 루트 모듈 한 파일로

### 3단계: AVM (Azure Verified Modules) 우선 사용

Microsoft가 검증한 Terraform 모듈을 **항상 먼저 검색**:
- 레지스트리: https://registry.terraform.io/namespaces/Azure
- 패턴: `Azure/avm-res-<resource-type>/azurerm`

**예시**:
```hcl
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.9"

  name                       = local.kv_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  enabled_for_disk_encryption = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
  tags = local.tags
}
```

AVM이 없는 리소스만 raw `azurerm_*` 직접 사용.

### 4단계: 핵심 파일 작성

#### `versions.tf`
```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
```

#### `backend.tf`
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "sttfstateprodkrc"
    container_name       = "tfstate"
    key                  = "order-platform.tfstate"
    use_azuread_auth     = true   # Managed Identity 권한으로 state 접근
  }
}
```

⚠️ Backend 리소스(RG + Storage + Container)는 **별도 부트스트랩 필요**.
없으면 사용자에게 다음 1회성 명령 안내:

```bash
# Backend 리소스 생성 (1회만)
RG=rg-tfstate-prod
SA=sttfstateprodkrc$RANDOM
LOC=koreacentral
az group create -n $RG -l $LOC
az storage account create -n $SA -g $RG -l $LOC \
  --sku Standard_GRS \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2
az storage container create --account-name $SA -n tfstate \
  --auth-mode login
echo "backend.tf의 storage_account_name을 '$SA'로 갱신"
```

#### `variables.tf`
```hcl
variable "location" {
  description = "Primary Azure region"
  type        = string
  default     = "koreacentral"
}

variable "environment" {
  description = "Environment name (dev/stg/prod)"
  type        = string
  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "environment must be one of: dev, stg, prod."
  }
}

variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# 시크릿은 절대 default 값 X
variable "sql_admin_password" {
  description = "Initial SQL admin password (rotate immediately)"
  type        = string
  sensitive   = true
}
```

#### `locals.tf` — 네이밍 컨벤션
`governance-check` 스킬과 일관되게:

```hcl
locals {
  # <type>-<workload>-<env>-<region>-<seq>
  rg_name      = "rg-${var.name_prefix}-${var.environment}-${substr(var.location, 0, 3)}"
  kv_name      = "kv-${var.name_prefix}-${var.environment}-${substr(var.location, 0, 3)}"
  aks_name     = "aks-${var.name_prefix}-${var.environment}-001"
  sql_name     = "sql-${var.name_prefix}-${var.environment}-${substr(var.location, 0, 3)}"
  # Storage는 lowercase + 영숫자
  storage_name = lower(replace("st${var.name_prefix}${var.environment}001", "-", ""))

  tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    module      = var.name_prefix
  })
}
```

#### `outputs.tf`
```hcl
output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "key_vault_uri" {
  value = module.key_vault.resource.vault_uri
}

output "aks_cluster_name" {
  description = "사용: az aks get-credentials -g <rg> -n <name>"
  value       = module.aks.name
}

output "sql_server_fqdn" {
  value     = module.sql.fqdn
  sensitive = false
}
```

#### `main.tf` — 루트 조립
```hcl
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.location
  tags     = local.tags
}

# Key Vault에서 SQL 패스워드 등 시크릿 가져오기
data "azurerm_key_vault" "shared" {
  name                = "kv-shared-${var.environment}-krc"
  resource_group_name = "rg-shared-${var.environment}-krc"
}

data "azurerm_key_vault_secret" "sql_admin" {
  name         = "sql-admin-password"
  key_vault_id = data.azurerm_key_vault.shared.id
}

module "network" {
  source              = "./modules/network"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  tags                = local.tags
}

module "key_vault" {
  source              = "Azure/avm-res-keyvault-vault/azurerm"
  version             = "~> 0.9"
  name                = local.kv_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

module "aks" {
  source              = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version             = "~> 0.2"
  name                = local.aks_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  # Managed Identity 우선
  managed_identities = {
    system_assigned = true
  }
  # ... AKS 상세 (인터뷰 결과 반영)
  tags = local.tags
}

# 시크릿은 KV 데이터 소스에서 받아 SQL에 주입
module "sql" {
  source              = "./modules/data"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  admin_password      = data.azurerm_key_vault_secret.sql_admin.value
  tags                = local.tags
}
```

### 5단계: 검증 및 결과 보고

생성 직후 다음을 자동 실행 (Bash):

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false   # backend 없이 syntax만 검증
terraform validate
```

검증 결과를 사용자에게 표 형태로:

```
## ✅ Terraform 생성 완료

**경로**: ./terraform/
**모듈**: 4개 (network, data, compute, identity)
**총 리소스**: 23개 (예상)

### 검증 상태
| 단계 | 결과 |
|---|---|
| terraform fmt | ✅ 통과 |
| terraform validate | ✅ 통과 |
| AVM 사용률 | 5/7 (71%) |

### 다음 단계
1. **Backend 부트스트랩 (필요시)**: 위 1회성 스크립트 실행
2. **시크릿 등록**: `az keyvault secret set --vault-name kv-shared-prod-krc -n sql-admin-password --value "..."`
3. **Init**: `cd terraform && terraform init`
4. **Plan**: `terraform plan -var-file=environments/prod.tfvars -out=tfplan`
5. **Plan 검토 후 Apply**: 저에게 "배포해줘"라고 요청 (사용자 명시 승인 시에만)
```

### 6단계 (사용자가 배포 요청한 경우): Plan 프리뷰

```bash
terraform plan -var-file=environments/prod.tfvars -out=tfplan
```

결과를 사용자에게 **표 형태로 요약**:

```
## 🔍 Terraform Plan 요약

**총 변경**: 23개 (생성 23, 수정 0, 삭제 0)

### 생성될 리소스
| # | 타입 | 이름 | 노트 |
|---|---|---|---|
| 1 | azurerm_resource_group | rg-order-prod-krc | |
| 2 | module.key_vault.azurerm_key_vault | kv-order-prod-krc | Premium SKU |
| 3 | module.aks.azurerm_kubernetes_cluster | aks-order-prod-001 | 3× D4s_v5, system MI |
| ... | ... | ... | ... |

### 시크릿 사용 (Key Vault에서 주입)
- sql_admin_password ← kv-shared-prod-krc/sql-admin-password

### 비용 영향 (cost-analyzer 권장)
견적: 약 ₩X,XXX,XXX/월 — 정확한 추정은 `cost-analyzer` 스킬에 위임

이대로 apply 하시겠습니까? (yes/no)
```

### 7단계: Apply 실행 (사용자 승인 후에만)

```bash
terraform apply tfplan
```

성공 시:
- 출력값(`outputs.tf`) 표 형태로 보고
- **Azure Portal 링크 제공** (필수):
  ```
  - Resource Group: https://portal.azure.com/#@<tenant>/resource/<rg-id>/overview
  - AKS: https://portal.azure.com/#@.../resource/<aks-id>/overview
  ```

## 기존 리소스 → Terraform import

"이미 만들어진 리소스를 Terraform 관리로 가져와줘" 요청 시:

```bash
# 1. 리소스 ID 조회
az resource list --resource-group <rg> --output json

# 2. .tf 파일에 빈 리소스 정의 작성 (또는 aztfexport 활용)

# 3. import
terraform import azurerm_resource_group.this /subscriptions/<sub-id>/resourceGroups/<rg>

# 4. terraform plan 으로 drift 확인
```

**대안**: `aztfexport` (Microsoft 공식 도구) 활용:

```bash
# 설치 후
aztfexport resource-group <rg-name> -o ./terraform-export
```

## 모범 사례 체크리스트

생성 후 확인:

- [ ] `azurerm` 버전 ~> 4.2 이상
- [ ] Backend 명시 (`backend "azurerm"`)
- [ ] AVM 우선 사용 (가능한 경우)
- [ ] `terraform fmt` 통과
- [ ] `terraform validate` 통과
- [ ] 시크릿이 코드에 평문 X (Key Vault data source만)
- [ ] Managed Identity 사용 (Service Principal 키 X)
- [ ] 모든 리소스에 `tags` 적용
- [ ] 네이밍 `governance-check` 컨벤션 일치
- [ ] `outputs.tf` 에 후속 모듈이 참조할 값 노출
- [ ] Variable에 `validation` 블록 (env 등 enum 타입)
- [ ] Sensitive variable에 `sensitive = true`
- [ ] `prevent_deletion_if_contains_resources = true` (RG)
- [ ] Storage/SQL/KV의 `min_tls_version = "1.2"`
- [ ] Public network access 명시적 제어

## 다른 컴포넌트로 위임
- ADR이 없으면 → `architecture-interview` 스킬로 먼저 설계
- 비용 검증 → `cost-analyzer` 스킬
- 네이밍·태그 사전 검증 → `governance-check` 스킬
- 보안 자세 점검 → `security-posture` 스킬 (배포 후)
- Bicep 형식이 필요하면 → `bicep-generator` 스킬

## 트러블슈팅

### `terraform init` 실패: backend access denied
- Storage Account에 `Storage Blob Data Contributor` 역할 필요
- `az role assignment create --assignee <upn> --role "Storage Blob Data Contributor" --scope <storage-id>`

### `terraform plan`이 항상 변경 감지
- `tags` 자동 부여 정책(Azure Policy)이 있으면 drift — `lifecycle { ignore_changes = [tags["..."]] }` 추가

### AVM 모듈 버전 충돌
- AVM 모듈끼리 transitive provider 버전 불일치 — 루트에서 명시적 `required_providers` 고정

## 참고 자료
- AzureRM Provider: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- Azure Verified Modules: https://aka.ms/avm
- Style Guide: https://developer.hashicorp.com/terraform/language/style
- aztfexport: https://github.com/Azure/aztfexport
