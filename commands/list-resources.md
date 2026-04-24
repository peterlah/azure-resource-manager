현재 활성 Azure 구독의 모든 리소스를 빠르게 조회합니다.

다음 단계를 수행하세요:

1. **인증 확인**
   ```bash
   az account show --query "name" --output tsv
   ```
   인증 실패 시 `/azure-resource-manager:az-login` 안내.

2. **리소스 그룹 목록**
   ```bash
   az group list --output table
   ```

3. **사용자에게 옵션 제시**
   - 전체 리소스 보기
   - 특정 리소스 그룹 선택
   - 특정 리소스 타입(VM, Storage 등)으로 필터링

4. **선택에 따라 실행**
   - 전체: `az resource list --output table`
   - RG 필터: `az resource list --resource-group <rg> --output table`
   - 타입 필터: `az resource list --resource-type Microsoft.Compute/virtualMachines --output table`

5. **결과 한국어 요약**
   - 총 리소스 수
   - 리소스 그룹별 분포
   - 주요 리소스 타입 Top 5

상세 분석이 필요하면 `resource-explorer` 스킬로 위임 권장.
