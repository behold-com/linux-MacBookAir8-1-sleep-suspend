# setup-t2-suspend.sh

Script de configuração de suspend/sleep para MacBook Air com chip T2 (MacBookAir8,1/8,2) rodando Ubuntu 26.04 LTS com kernel t2-resolute.

## Sistema Compatível

- **Hardware**: MacBook Air 2018/2019 (MacBookAir8,1 e MacBookAir8,2)
- **Sistema**: Ubuntu 26.04 LTS
- **Kernel**: t2-resolute (kernel patcheado para suporte Apple T2)

## Funcionalidades

Este script configura automaticamente o sistema para permitir suspend/sleep estável em Macs com chip T2:

### 1. Configuração do Kernel (GRUB)
- Define `mem_sleep_default=s2idle` como parâmetro de kernel
- Atualiza o GRUB com a nova configuração
- O modo s2idle é necessário para o T2 funcionar corretamente

### 2. Configuração do systemd (sleep.conf)
- Força o uso de s2idle como estado de suspend
- Desabilita hibernação (não suportada no T2)
- Desabilita hybrid sleep e suspend-then-hibernate

### 3. Configuração do systemd (logind.conf)
- Configura o comportamento ao fechar a tampa (lid switch)
- Define ação de idle como ignore
- Suspend ao fechar tampa (com ou sem energia externa)

### 4. Regras udev para Thunderbolt
- Desabilita async resume no controlador Thunderbolt xHCI
- Previne erro -19 durante suspend/resume
- Aplica regras PCI específicas para o T2

### 5. Script de Desabilitação de Wakeup Sources
- Desabilita fontes de wakeup espúrias (XHC2, RP01, RP05, RP09, ARPT)
- Previne acordamentos indesejados durante suspend
- Executado automaticamente na inicialização

### 6. Script Helper Pre-Suspend
- Salva estado da bateria antes de suspender
- Remove módulos do kernel (BCE e WiFi) antes do suspend
- Previne conflitos durante o ciclo de suspend

### 7. Script Helper Pós-Resume
- Recarrega módulos BCE e WiFi após resume
- Gera log detalhado do ciclo de suspend/resume
- Calcula drenagem de bateria durante o sleep
- Reporta erros encontrados nos logs do sistema

### 8. Serviços Systemd
- **disable-xhc2-wakeup.service**: Desabilita wakeup sources no boot
- **suspend-fix-t2.service**: Gerencia pre/post suspend hooks
- **t2-post-resume.service**: Executa recuperação pós-resume de forma assíncrona

### 9. Aplicação Imediata
- Aplica configurações sem necessidade de reboot imediato
- Recarrega regras udev e logind
- Ajusta wakeup sources em runtime

## Como Usar

Execute o script como root:

```bash
sudo bash ~/setup-t2-suspend.sh
```

Após a execução, **reinicie o sistema** para que as alterações do GRUB entrem em efeito.

## Avisos Importantes

### ⚠️ Erros Potenciais

1. **Erro -19 no Thunderbolt**: Se ocorrer erro -19 durante suspend, verifique se a regra udev foi aplicada corretamente e se o arquivo `/sys/bus/pci/devices/0000:06:00.0/power/async` contém "disabled".

2. **Wake espúrio**: Se o Mac acordar sozinho, verifique as fontes de wakeup em `/proc/acpi/wakeup`. O script tenta desabilitar as principais, mas pode ser necessário ajuste manual.

3. **WiFi não funciona após resume**: Se o WiFi não retornar após resume, verifique os logs com `journalctl -u t2-post-resume.service` para identificar o problema.

4. **Hardware incompatível**: O script verifica se o hardware é MacBookAir8,1/8,2. Se executado em outro modelo, pode não funcionar corretamente.

### ⚠️ Comportamento Específico do T2

- **Acordar do suspend**: Use o **botão de power** para acordar. Este é o comportamento normal no T2 com s2idle.
- **Teclado/trackpad**: Não funcionam para acordar do suspend no T2.
- **Hibernação**: Não é suportada e foi desabilitada intencionalmente.

## Verificação

Após a execução, o script mostra um resumo das configurações aplicadas:
- Parâmetro mem_sleep_default no GRUB
- Estado das fontes ACPI wakeup
- Estado do async do Thunderbolt xHCI
- Status dos serviços systemd

## Logs

Os logs do ciclo de suspend/resume podem ser verificados com:

```bash
journalctl -u t2-post-resume.service
journalctl -u suspend-fix-t2.service
```

## Requisitos

- `dmidecode` (para verificação de hardware)
- `rg` (ripgrep) para análise de logs
- Acesso root (sudo)

## Suporte

Este script foi desenvolvido especificamente para MacBook Air com chip T2 rodando Ubuntu 26.04 LTS com kernel t2-resolute. Outras versões do Ubuntu ou distribuições podem requerer ajustes.
