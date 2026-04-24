---
description: Azure 리소스의 네이밍 컨벤션, 필수 태그, 리전 정책 등 거버넌스 규칙 준수 여부를 검증합니다. 사용자가 "거버넌스 점검", "네이밍 검증", "태그 누락 확인", "정책 준수" 등을 요청할 때 사용
---

# Azure Governance Check

조직의 거버넌스 정책 준수 여부를 검증합니다.

## 사용 시점
- 신규 리소스 생성 전 사전 검증
- 기존 리소스의 정책 위반 항목 감사
- 신규 거버넌스 규칙 도입 시 영향도 분석

## 기본 검증 규칙

### 네이밍 컨벤션 (Azure CAF 기반)
| 리소스 타입 | 접두사 | 예시 |
|-----------|------|------|
| Resource Group | `rg-` | `rg-shared-prod-koreacentral` |
| Virtual Machine | `vm-` | `vm-web-prod-001` |
| Storage Account | `st` | `stsharedprodkrc001` (소문자, 숫자만) |
| Key Vault | `kv-` | `kv-shared-prod-krc` |
| Virtual Network | `vnet-` | `vnet-hub-prod-koreacentral` |
| AKS Cluster | `aks-` | `aks-platform-prod-001` |
| Log Analytics | `log-` | `log-shared-prod` |

**규칙**
- 소문자 + 하이픈 (Storage 제외)
- `<type>-<workload>-<env>-<region>-<seq>` 형식
- env: `dev` / `stg` / `prod`
- region: `koreacentral` / `koreasouth` / `eastus` 등

### 필수 태그
모든 리소스에 다음 태그 필수:
- `environment`: dev | stg | prod
- `owner`: 이메일 또는 팀명
- `cost-center`: 비용 부서 코드
- `created-by`: terraform | manual | claude-plugin

### 리전 정책
- 기본 리전: `koreacentral`
- 허용 리전: `koreacentral`, `koreasouth`, `japaneast` (DR용)
- 그 외 리전 사용 시 경고

### 보안 기본값
- Storage Account: HTTPS only, 최소 TLS 1.2
- Key Vault: Soft Delete + Purge Protection 활성
- Network Security Group: 0.0.0.0/0 SSH/RDP 차단
- Public IP: 명시적 승인 필요

## 워크플로우

### 단일 리소스 검증
1. Azure MCP로 대상 리소스 속성 조회
2. 위 규칙 대조
3. 위반 항목 리포트

### 구독 전체 감사
1. Azure Resource Graph로 전체 리소스 조회
2. 각 리소스에 규칙 적용
3. 위반 카테고리별 집계

### 보고서 형식

```
## 🛡️ 거버넌스 검증 결과

**대상**: <구독/RG/리소스>
**검증 일시**: 2026-04-24 16:30
**준수율**: XX% (XXX/YYY)

### ❌ 위반 항목

#### 네이밍 위반 (X건)
- `myStorageAcc01` → 권장: `stworkloadprodkrc001`

#### 필수 태그 누락 (X건)
- `vm-web-001`: owner, cost-center 누락

#### 리전 정책 위반 (X건)
- `vm-test-westus`: 허용되지 않은 리전 (westus)

### 🔧 권장 조치
1. <리소스명>: 다음 명령으로 태그 추가
   ```bash
   az resource tag --tags owner=peterlah cost-center=eng ...
   ```
```

## 정책 커스터마이징
사용자가 자체 규칙을 정의하고 싶다면 이 SKILL.md를 fork하거나 별도 정책 파일 추가 가능.
