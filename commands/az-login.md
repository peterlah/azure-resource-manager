Azure CLI 로그인 및 인증 상태를 확인합니다.

다음 단계를 수행하세요:

1. **현재 인증 상태 확인**
   ```bash
   az account show --output table
   ```

2. **로그인 필요 시 안내**
   - 위 명령이 실패하면 다음 명령을 사용자에게 안내:
   ```bash
   az login
   ```
   - 디바이스 코드 방식이 필요하면:
   ```bash
   az login --use-device-code
   ```

3. **다중 구독인 경우 활성 구독 확인**
   ```bash
   az account list --output table
   ```
   - 사용자에게 어떤 구독을 활성화할지 묻기
   - 변경 시: `az account set --subscription "<구독명-또는-ID>"`

4. **결과 보고**
   - 활성 구독, 테넌트, 사용자 계정을 한국어로 요약
   - Azure MCP 서버가 이 인증을 자동 사용함을 안내
