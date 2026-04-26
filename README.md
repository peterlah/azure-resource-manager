# azure-resource-manager

Azure Resource Manager 통합 Claude Code 플러그인. Microsoft 공식 [Azure MCP Server](https://github.com/Azure/azure-mcp)를 래핑하여 자연어로 Azure 리소스를 관리합니다.

## 주요 기능

- **자연어 Azure 조작** — "koreacentral의 VM 다 보여줘", "rg-test 삭제해줘" 등
- **거버넌스 검증** — 네이밍, 태그, 리전 정책 자동 점검
- **비용 분석** — 월간 비용, 이상 탐지, 최적화 제안
- **아키텍처 컨설팅** — Well-Architected Framework 기반 설계 자문
- **장애 진단** — Resource Health · Activity Log · App Insights · Advisor 다층 분석으로 RCA
- **보안 자세 점검** — 공개 노출, NSG, RBAC, Key Vault, Defender Secure Score 통합 진단 (azqr 통합)
- **인터뷰 기반 아키텍처 설계** — 구조화된 Q&A → Mermaid(인라인) + Drawpyo→drawio(MS Learn 스타일 공식 Azure 아이콘) 다이어그램 + ADR + 비용 추정
- **Terraform IaC 생성** — ADR → AVM 우선 Terraform 모듈 (Managed Identity, Key Vault 시크릿, 원격 state)
- **한국어 우선** — 모든 응답이 한국어로 작성됨

## 사전 요구사항

| 도구 | 버전 | 설치 |
|------|------|------|
| Azure CLI | ≥ 2.50 | `brew install azure-cli` |
| Node.js | ≥ 18 | `brew install node` (npx용) |
| Claude Code | ≥ 3.0 | [공식 사이트](https://claude.com/claude-code) |
| Python 3 + Drawpyo | ≥ 3.9 | `pip install drawpyo` (architecture-interview 다이어그램용, 옵션) |
| drawio | desktop/web | https://app.diagrams.net/ 또는 VS Code "Draw.io Integration" 확장 (다이어그램 렌더, 옵션) |

## 설치

### 1. Azure 로그인 (최초 1회)

```bash
az login
az account set --subscription "<구독명-또는-ID>"
```

### 2. 플러그인 설치

Claude Code 세션에서 아래 두 줄만 실행하면 됩니다.

```
/plugin marketplace add peterlah/azure-resource-manager
/plugin install azure-resource-manager@peterlah-plugins
```

첫 줄은 마켓플레이스를 등록하고, 둘째 줄이 실제 플러그인을 설치합니다. 이후 `/plugin` 명령으로 업데이트·제거가 가능합니다.

**로컬 개발용 (리포지토리를 clone해서 수정하려는 경우)**

```
/plugin marketplace add ./path/to/azure-resource-manager
/plugin install azure-resource-manager@peterlah-plugins
```

### 3. 설치 확인

Claude Code 세션에서:

```
/azure-resource-manager:current-context
```

활성 구독이 표시되면 정상 동작.

## 사용법

### Slash Commands (수동 호출)

| 커맨드 | 설명 |
|-------|------|
| `/azure-resource-manager:az-login` | Azure 인증 상태 확인 및 로그인 |
| `/azure-resource-manager:list-resources` | 빠른 리소스 목록 조회 |
| `/azure-resource-manager:current-context` | 현재 구독/테넌트 컨텍스트 확인 |
| `/azure-resource-manager:incident <리소스>` | 장애·이상 동작 1차 진단 (Service/Resource Health · Activity Log · 핵심 메트릭) |
| `/azure-resource-manager:security-scan [quick\|standard\|deep]` | 보안 자세 빠른 점검 (공개 노출 · Defender · Key Vault · RBAC · azqr) |
| `/azure-resource-manager:architect <한 줄 요구>` | 인터뷰 → Mermaid + D2 다이어그램 + ADR + Terraform 한 흐름 |

### Skills (자연어 자동 호출)

이런 식으로 말하면 Claude가 자동으로 적절한 스킬을 사용합니다:

- "프로덕션 리소스 그룹 어떤 게 있어?" → **resource-explorer**
- "rg-test에 Storage 계정 만들어줘" → **resource-deploy**
- "이번 달 Azure 요금 분석해줘" → **cost-analyzer**
- "우리 구독 거버넌스 점검해줘" → **governance-check**
- "이 요구사항으로 Bicep 파일 짜줘" → **bicep-generator**
- "app-prod에 5xx 떠요, 왜?" → **incident-investigator**
- "공개 노출된 리소스 있어?" / "Defender 점수 알려줘" → **security-posture**
- "신규 시스템 아키텍처 그려줘" / "인터뷰로 설계 도와줘" → **architecture-interview**
- "이 ADR로 Terraform 짜줘" / "AKS+SQL Terraform" → **terraform-generator**

### Agent (복잡한 설계·진단 위임)

복잡한 아키텍처 의사결정은 `azure-architect` 에이전트로 자동 위임됩니다:

- "AKS와 Container Apps 중 뭘 써야 해?"
- "한국 리전에서 Hub-Spoke 네트워크 설계해줘"

다단계 RCA(Root Cause Analysis)는 `azure-troubleshooter` 에이전트로 위임됩니다:

- "어제 14시에 5xx 폭주했는데 근본 원인 분석해줘"
- "AKS → SQL → Storage 체인 어디가 병목인지 추적해줘"

종합 보안 감사·컴플라이언스 매핑은 `azure-security-auditor` 에이전트로 위임됩니다:

- "MCSB 기준으로 prod 구독 감사 보고서 만들어줘"
- "ISO 27001 통제별로 갭 분석"

## 디렉토리 구조

```
azure-resource-manager/
├── .claude-plugin/
│   ├── plugin.json              # 플러그인 메니페스트
│   └── marketplace.json         # /plugin install을 위한 마켓플레이스 정의
├── .mcp.json                    # Azure 공식 MCP 서버 등록
├── skills/
│   ├── resource-explorer/       # 리소스 조회 스킬
│   ├── resource-deploy/         # 리소스 CUD 스킬 (안전 가드 포함)
│   ├── cost-analyzer/           # 비용 분석 스킬
│   ├── governance-check/        # 정책 검증 스킬
│   ├── bicep-generator/         # 자연어 → Bicep IaC 변환 스킬
│   ├── incident-investigator/   # 장애·이상 동작 다층 진단 스킬
│   ├── security-posture/        # 보안 자세 통합 점검 스킬 (azqr 통합)
│   ├── architecture-interview/  # 인터뷰 → Mermaid+Drawpyo→drawio 다이어그램 + ADR + 비용 추정
│   └── terraform-generator/     # ADR → AVM 우선 Terraform 모듈 변환
├── commands/
│   ├── az-login.md
│   ├── list-resources.md
│   ├── current-context.md
│   ├── incident.md              # 장애 1차 진단 빠른 실행
│   ├── security-scan.md         # 보안 자세 빠른 점검
│   └── architect.md             # 인터뷰 + 다이어그램 + ADR + IaC 한 흐름
├── agents/
│   ├── azure-architect.md       # WAF 기반 아키텍처 에이전트
│   ├── azure-troubleshooter.md  # 다단계 RCA 진단 에이전트
│   └── azure-security-auditor.md # 컴플라이언스 기반 종합 보안 감사 에이전트
├── hooks/
│   ├── hooks.json               # PreToolUse hook 등록
│   └── check-az-destructive.sh  # 위험한 az 명령 차단 스크립트
├── .gitignore
└── README.md
```

## 인증

이 플러그인은 **Azure CLI 인증을 우선** 사용합니다 (`az login`).

다른 인증 방식이 필요하면 `.mcp.json`의 환경변수를 수정:

```json
{
  "mcpServers": {
    "azure": {
      "env": {
        "AZURE_CLIENT_ID": "...",
        "AZURE_CLIENT_SECRET": "...",
        "AZURE_TENANT_ID": "..."
      }
    }
  }
}
```

자세한 인증 옵션은 [Azure MCP Authentication 문서](https://github.com/Azure/azure-mcp/blob/main/docs/Authentication.md) 참조.

## 안전 원칙

이 플러그인은 다음 원칙을 따릅니다:

- ✅ **모든 변경 작업 사전 승인** — 생성/수정/삭제 전 사용자 확인 필수
- ✅ **삭제 이중 확인** — 리소스 이름 재입력 요구
- ✅ **시크릿 보호** — 키, 연결 문자열 평문 출력 금지
- ❌ **자동 `--yes` 플래그 금지**
- ❌ **프로덕션 일괄 작업 금지**

### Pre-ToolUse Hook (v0.2.0+)

프롬프트 레벨의 안전 가드에 더해, 플러그인은 **harness 레벨 Hook**으로 다음 위험한 Azure CLI 명령을 자동 차단합니다:

| 차단 대상 | 이유 |
|---|---|
| `az group delete` | 리소스 그룹 전체를 한 번에 날림 — 사용자가 터미널에서 직접 실행해야 함 |
| `az ... (delete\|purge\|remove) --yes` / `-y` | 자동 승인 삭제 금지 |
| `az keyvault [secret\|key\|certificate] purge` | soft-delete 영구 삭제로 복구 불가 |

차단된 경우 Claude에게 차단 사유가 전달되어, 사용자에게 명시적 확인을 요청하도록 유도합니다. Hook 구현: `hooks/check-az-destructive.sh` (Python 3 필요 — macOS 기본 포함).

## 트러블슈팅

### "Azure MCP 서버에 연결할 수 없음"
1. `npx -y @azure/mcp@latest --version` 실행 → 에러 없는지 확인
2. Node.js 18+ 설치 확인: `node --version`
3. Claude Code 세션에서 `/reload-plugins` 실행

### "인증 실패"
1. `az account show` 실행 → 활성 구독 있는지 확인
2. 없다면 `az login` 재실행
3. 다중 테넌트면 `az login --tenant <tenant-id>`

### "권한 부족"
- 사용 중인 계정에 필요한 RBAC 권한 부여 확인
- 최소 권한: `Reader` (조회), `Contributor` (변경)

## 개발

플러그인 수정 후 변경사항 반영:

```
/reload-plugins
```

새 스킬 추가:

```bash
mkdir -p skills/<skill-name>
# SKILL.md 작성 (frontmatter 필수)
/reload-plugins
```

## 라이선스

MIT

## 관련 링크

- [Azure MCP Server (공식)](https://github.com/Azure/azure-mcp)
- [Azure CLI 문서](https://learn.microsoft.com/cli/azure/)
- [Claude Code 플러그인 가이드](https://code.claude.com/docs/en/plugins.md)
- [Azure Well-Architected Framework](https://learn.microsoft.com/azure/well-architected/)
