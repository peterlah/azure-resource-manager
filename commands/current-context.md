현재 Azure 작업 컨텍스트를 표시합니다 (구독, 테넌트, 기본 리전, 인증 정보).

다음을 수집하여 한국어로 보고하세요:

1. **활성 구독 정보**
   ```bash
   az account show --output json
   ```

2. **사용 가능한 모든 구독 목록**
   ```bash
   az account list --query "[].{Name:name, ID:id, IsDefault:isDefault}" --output table
   ```

3. **기본 리전 설정 확인**
   ```bash
   az config get defaults.location 2>/dev/null
   ```

4. **CLI 버전 확인**
   ```bash
   az --version | head -1
   ```

5. **다음 형식으로 보고**

```
## 🔵 Azure 컨텍스트

**활성 구독**: <구독명>
**구독 ID**: <ID>
**테넌트**: <테넌트명/ID>
**계정**: <user@example.com>
**기본 리전**: <region 또는 "미설정">
**Azure CLI**: <버전>

### 사용 가능한 다른 구독
| 이름 | ID | 활성 |
|-----|-----|------|
| ... | ... | ... |

전환하려면: `az account set --subscription "<이름>"`
```
