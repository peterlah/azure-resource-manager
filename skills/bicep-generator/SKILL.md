---
description: 자연어 요구사항을 Azure Bicep IaC 템플릿으로 변환합니다. 사용자가 "Bicep 만들어줘", "IaC 템플릿 작성", "ARM 템플릿으로 짜줘", "Infrastructure as Code", "Bicep으로 변환" 등을 요청할 때 사용
---

# Azure Bicep Generator

자연어 요구사항을 검증된 Bicep 파일로 변환합니다. 기본 동작은 **파일 생성만**이며, 배포는 사용자의 명시적 요청 시에만 수행합니다.

## 사용 시점
- "koreacentral에 Premium 스토리지 계정 만드는 Bicep 짜줘"
- "AKS + ACR + Key Vault를 묶은 IaC 템플릿 작성"
- "기존 `az` 명령 대신 Bicep으로 관리하고 싶어"
- "이 Bicep을 ARM JSON으로 변환"

`resource-deploy` 스킬과의 차이:
- `resource-deploy` — `az create/update/delete`로 **즉시 반영** (명령형)
- `bicep-generator` — **선언형 IaC 파일 생성**, 팀 공유·Git 관리·재현 가능 배포에 적합

## ⚠️ 안전 원칙

### 기본값: 파일 생성만
사용자가 명시적으로 "배포해줘" / "deploy" / "올려줘"라고 말하지 않으면 **파일만 생성**하고 끝냅니다. 배포 여부는 항상 파일 검토 후 사용자에게 결정권을 넘깁니다.

### 시크릿 하드코딩 금지
- 비밀번호, 키, 연결 문자열은 **절대 Bicep 본문에 넣지 말 것**
- 반드시 `@secure() param` 으로 선언하고 `.bicepparam` 또는 Key Vault reference로 주입
- 예시 값이 필요하면 `<YOUR-PASSWORD-HERE>` 같은 명시적 플레이스홀더 사용

### 배포 전 필수 검증
1. `az bicep build` — 문법 검증 (ARM JSON 변환 성공 여부)
2. `az deployment group what-if` — 실제 변경사항 프리뷰
3. 사용자 승인 후에만 `az deployment group create`

## 워크플로우

### 1단계: 요구사항 구조화

사용자 입력을 다음 형식으로 정리하고 누락된 항목은 **명시적으로 질문**:

```
## 📋 요구사항 파악

- **리소스 타입**: Storage Account
- **이름**: (사용자에게 물어보거나 네이밍 컨벤션 제안)
- **리소스 그룹**: peterlah (기본값 사용, 변경 가능)
- **리전**: koreacentral
- **SKU**: Premium_LRS
- **주요 속성**: HTTPS-only, blob public access 차단, TLS 1.2+
- **태그**: env=dev, owner=<user>
```

### 2단계: 정확한 스키마 조회

Azure MCP의 `bicepschema` 도구로 해당 리소스 타입의 최신 API 버전과 속성을 확인한 뒤 작성. **추측으로 속성 이름 쓰지 말 것** — API 버전이 맞지 않으면 배포 시 에러.

### 3단계: Bicep 파일 생성

**파일 구조 원칙**
- 단일 리소스는 `main.bicep` 하나로
- 여러 리소스면 모듈 분리 (`modules/storage.bicep`, `modules/network.bicep`)
- 파라미터는 `main.bicepparam` 로 분리 권장

**권장 템플릿 구조**

```bicep
// main.bicep
targetScope = 'resourceGroup'

@description('배포 리전')
param location string = resourceGroup().location

@description('리소스 이름 접두사')
param namePrefix string

@description('환경 태그')
param tags object = {
  env: 'dev'
  managedBy: 'bicep'
}

// ... resource 블록

output storageAccountId string = storage.id
output primaryEndpoint string = storage.properties.primaryEndpoints.blob
```

**필수 체크리스트**
- [ ] `targetScope` 명시
- [ ] 모든 `param`에 `@description`
- [ ] 리소스마다 최신 API 버전 (`2024-xx-xx` 형식)
- [ ] 하드코딩 값 최소화 — 파라미터로 추출
- [ ] `output`으로 후속 모듈이 참조할 값 노출
- [ ] 보안 기본값: HTTPS-only, Public access 차단, 최신 TLS

### 4단계: 파일 생성 후 검증

```bash
az bicep build --file main.bicep
```

성공 시 `main.json` (ARM 템플릿) 생성 확인. 실패 시 에러 메시지를 그대로 사용자에게 보이고 수정.

### 5단계: 결과 보고

```
## ✅ Bicep 파일 생성 완료

**경로**: ./main.bicep
**파라미터**: ./main.bicepparam (있다면)
**검증**: az bicep build 통과 ✅
**리소스 개수**: 3 (Storage Account, Blob Container, Role Assignment)

### 다음 단계
1. 파일 검토: `code main.bicep`
2. 변경 프리뷰: `az deployment group what-if -g peterlah -f main.bicep`
3. 배포 실행: 위 프리뷰 확인 후 저에게 "배포해줘"라고 요청
```

### 6단계 (사용자가 배포 요청한 경우): What-If 프리뷰

```bash
az deployment group what-if \
  --resource-group <rg> \
  --template-file main.bicep \
  --parameters main.bicepparam
```

결과를 사용자에게 **표 형태로 요약**해서 보여주고 승인 대기:

```
## 🔍 배포 프리뷰 (What-If)

| 작업 | 리소스 | 변경사항 |
|---|---|---|
| Create | Microsoft.Storage/storageAccounts/stdev001 | (신규) |
| Modify | Microsoft.Storage/storageAccounts/existing | tags.env: "test" → "dev" |

총 변경: 생성 1, 수정 1, 삭제 0

이대로 배포하시겠습니까? (yes/no)
```

### 7단계: 배포 실행

사용자 승인 후에만:

```bash
az deployment group create \
  --resource-group <rg> \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --name "deploy-$(date +%Y%m%d-%H%M%S)"
```

## 기존 리소스 → Bicep 역변환

"이미 만들어진 스토리지 계정을 Bicep으로 바꿔줘" 요청 시:

```bash
az resource show --ids <resource-id> --output json > existing.json
# 또는
az bicep decompile --file existing.json
```

`decompile` 결과는 관례상 정제 필요 — 다음을 자동 점검:
- 하드코딩된 이름을 파라미터로 승격
- Location을 `resourceGroup().location`으로 교체
- 불필요한 기본값 속성 제거
- 시크릿이 있으면 `@secure() param`으로 이전

## 모범 사례

### 네이밍
모듈과 리소스는 `camelCase`, 리소스명 자체는 Azure 네이밍 컨벤션(`governance-check` 참조).

### 반복 리소스
```bicep
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = [for name in containerNames: {
  parent: blobService
  name: name
}]
```

### 조건부 배포
```bicep
resource privateEndpoint '...' = if (usePrivateEndpoint) { ... }
```

### 모듈화 판단 기준
- 3개 이상 리소스가 묶이면 → 모듈 분리
- 다른 구독·RG에서 재사용 가능성 있으면 → 모듈 + 버전 관리

## 제약 사항
- 이 스킬은 **파일을 만들 뿐** — 실제 테스트는 `az deployment group what-if`로 검증
- Bicep이 지원하지 않는 Azure 리소스(드문 사례)는 ARM JSON으로 폴백 필요
- 크로스 구독 배포는 `targetScope = 'subscription'` + 별도 권한 필요
