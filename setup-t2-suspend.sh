#!/bin/bash
# =============================================================================
# setup-t2-suspend.sh — Configuração de suspend/sleep para MacBookAir8,1 (T2)
# Ubuntu 26.04 LTS | Kernel t2-resolute
#
# Execute como root: sudo bash ~/setup-t2-suspend.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[ERRO]${NC}  $*"; exit 1; }
section() { echo -e "\n${YELLOW}=== $* ===${NC}"; }

# --- Verificação de privilégio ---
[ "$(id -u)" -eq 0 ] || fail "Execute com sudo: sudo bash $0"

# --- Verificação de hardware ---
PRODUCT=$(dmidecode -t system 2>/dev/null | awk '/Product Name/{print $NF}')
if [[ "${PRODUCT}" != "MacBookAir8,1" && "${PRODUCT}" != "MacBookAir8,2" ]]; then
    warn "Produto detectado: '${PRODUCT}'. Este script foi feito para MacBookAir8,1/8,2."
    read -rp "Continuar mesmo assim? [s/N] " resp
    [[ "${resp,,}" == "s" ]] || exit 0
fi

# =============================================================================
section "1. Parâmetro de kernel — mem_sleep_default=s2idle"
# =============================================================================
GRUB_FILE=/etc/default/grub

if grep -q "mem_sleep_default=s2idle" "${GRUB_FILE}"; then
    ok "mem_sleep_default=s2idle já configurado"
else
    cp "${GRUB_FILE}" "${GRUB_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    sed -i 's/mem_sleep_default=deep/mem_sleep_default=s2idle/g' "${GRUB_FILE}"
    if ! grep -q "mem_sleep_default" "${GRUB_FILE}"; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mem_sleep_default=s2idle"/' "${GRUB_FILE}"
    fi
    update-grub 2>/dev/null | tail -3
    ok "mem_sleep_default=s2idle aplicado e grub atualizado"
fi

# =============================================================================
section "2. systemd sleep.conf — forçar s2idle, desabilitar hibernate"
# =============================================================================
mkdir -p /etc/systemd/sleep.conf.d
cat > /etc/systemd/sleep.conf.d/t2-mac.conf << 'EOF'
[Sleep]
AllowSuspend=yes
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
SuspendState=freeze
EOF
ok "sleep.conf.d/t2-mac.conf criado"

# =============================================================================
section "3. logind.conf — lid switch e idle"
# =============================================================================
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/t2-mac.conf << 'EOF'
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
ok "logind.conf.d/t2-mac.conf criado"

# =============================================================================
section "4. udev rule — Thunderbolt xHCI async resume (previne erro -19)"
# =============================================================================
cat > /etc/udev/rules.d/99-t2-pci-pm.rules << 'EOF'
# Thunderbolt xHCI (XHC2) on T2 MacBookAir8,1 — disable async resume to prevent -19 error
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15ec", ATTR{power/async}="disabled"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15ec", ATTR{power/control}="auto"
EOF
udevadm control --reload-rules
ok "99-t2-pci-pm.rules criado e recarregado"

# =============================================================================
section "5. Script helper — desabilitar wakeup sources espúrios"
# =============================================================================
mkdir -p /usr/local/libexec
cat > /usr/local/libexec/disable-wakeup-sources.sh << 'EOF'
#!/bin/bash
# Desabilita wakeup sources que causam wake espúrio no MacBookAir8,1 (T2)
for dev in XHC2 RP01 RP05 RP09 ARPT; do
    state=$(awk -v d="$dev" '$1==d{print $3}' /proc/acpi/wakeup)
    [ "$state" = "*enabled" ] && echo "$dev" > /proc/acpi/wakeup || true
done

# Desabilita async resume no Thunderbolt xHCI (XHC2) para prevenir erro -19
TB_XHCI=/sys/bus/pci/devices/0000:06:00.0/power/async
[ -f "${TB_XHCI}" ] && echo disabled > "${TB_XHCI}" || true
EOF
chmod 755 /usr/local/libexec/disable-wakeup-sources.sh
ok "disable-wakeup-sources.sh criado"

# =============================================================================
section "6. Script helper — pre/post suspend (BCE + WiFi)"
# =============================================================================
cat > /usr/local/libexec/t2-suspend-helper.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

log() { logger -t t2-suspend-helper "$*"; }

state_dir=/run/t2-suspend-helper

snapshot_battery_state() {
  local bat= ac= f
  install -d -m 0755 "${state_dir}"
  printf '%s\n' "$(date +%s)" > "${state_dir}/pre_epoch"
  for bat in /sys/class/power_supply/BAT*; do [[ -d "${bat}" ]] && break; done
  if [[ -n "${bat}" && -d "${bat}" ]]; then
    printf '%s\n' "${bat}" > "${state_dir}/battery_path"
    for f in status capacity energy_now energy_full charge_now charge_full voltage_now current_now power_now; do
      if [[ -f "${bat}/${f}" ]]; then cat "${bat}/${f}" > "${state_dir}/${f}"; else rm -f "${state_dir}/${f}"; fi
    done
  fi
  for ac in /sys/class/power_supply/ADP* /sys/class/power_supply/AC*; do [[ -f "${ac}/online" ]] && break; done
  if [[ -n "${ac}" && -f "${ac}/online" ]]; then cat "${ac}/online" > "${state_dir}/ac_online"; else rm -f "${state_dir}/ac_online"; fi
}

case "${1:-}" in
  pre)
    log "pre: unloading BCE/Wi-Fi"
    snapshot_battery_state
    modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
    rmmod -f apple-bce 2>/dev/null || true
    log "pre: complete"
    ;;
  post)
    log "post: starting t2-post-resume.service"
    systemctl reset-failed t2-post-resume.service 2>/dev/null || true
    if systemctl start --no-block t2-post-resume.service 2>/dev/null; then
      log "post: queued t2-post-resume.service"
    else
      log "post: failed to queue t2-post-resume.service"
    fi
    ;;
  *) echo "usage: $0 pre|post" >&2; exit 2 ;;
esac
SCRIPT
chmod 755 /usr/local/libexec/t2-suspend-helper.sh
ok "t2-suspend-helper.sh criado"

# =============================================================================
section "7. Script helper — pós-resume (recarrega BCE + WiFi)"
# =============================================================================
cat > /usr/local/libexec/t2-post-resume.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

log() { logger -t t2-post-resume "$*"; }

log_summary_row() {
  local row
  printf -v row '| %-20s | %-25s |' "$1" "$2"
  log "$row"
}

format_ratio_pct() {
  awk -v n="$1" -v f="$2" 'BEGIN { if (f > 0) printf "%.2f", (100 * n) / f; else printf "n/a"; }'
}

detect_ac_online() {
  local ac
  for ac in /sys/class/power_supply/ADP* /sys/class/power_supply/AC*; do
    [[ -f "${ac}/online" ]] || continue
    cat "${ac}/online"
    return 0
  done
  return 1
}

log_battery_summary() {
  local slept_seconds=$1
  local state_dir=/run/t2-suspend-helper
  local bat_path ac_before_raw ac_after_raw before_src after_src
  local before_now before_full after_now after_full before_pct after_pct
  local delta_u delta_text rate_text

  [[ -d "${state_dir}" ]] || return 0
  bat_path="$(cat "${state_dir}/battery_path" 2>/dev/null || true)"
  if [[ -z "${bat_path}" || ! -d "${bat_path}" ]]; then
    for bat_path in /sys/class/power_supply/BAT*; do [[ -d "${bat_path}" ]] && break; done
  fi
  [[ -n "${bat_path}" && -d "${bat_path}" ]] || return 0

  ac_before_raw="$(cat "${state_dir}/ac_online" 2>/dev/null || true)"
  ac_after_raw="$(detect_ac_online 2>/dev/null || true)"
  [[ -n "${ac_before_raw}" ]] && before_src="$([[ "${ac_before_raw}" == "1" ]] && echo AC || echo Battery)"
  [[ -n "${ac_after_raw}" ]] && after_src="$([[ "${ac_after_raw}" == "1" ]] && echo AC || echo Battery)"

  if [[ -f "${state_dir}/charge_now" && -f "${bat_path}/charge_now" ]]; then
    before_now="$(cat "${state_dir}/charge_now")"; before_full="$(cat "${state_dir}/charge_full")"
    after_now="$(cat "${bat_path}/charge_now")";   after_full="$(cat "${bat_path}/charge_full")"
    before_pct="$(format_ratio_pct "${before_now}" "${before_full}")"
    after_pct="$(format_ratio_pct "${after_now}" "${after_full}")"
    delta_u=$((before_now - after_now))
    delta_text="$(awk -v d="${delta_u}" 'BEGIN { printf "%.2f mAh", d / 1000.0 }')"
    rate_text="$(awk -v d="${delta_u}" -v s="${slept_seconds}" 'BEGIN { if (s > 0) printf "%.2f mA", (d / 1000.0) / (s / 3600.0); else printf "n/a"; }')"
  elif [[ -f "${state_dir}/energy_now" && -f "${bat_path}/energy_now" ]]; then
    before_now="$(cat "${state_dir}/energy_now")"; before_full="$(cat "${state_dir}/energy_full")"
    after_now="$(cat "${bat_path}/energy_now")";   after_full="$(cat "${bat_path}/energy_full")"
    before_pct="$(format_ratio_pct "${before_now}" "${before_full}")"
    after_pct="$(format_ratio_pct "${after_now}" "${after_full}")"
    delta_u=$((before_now - after_now))
    delta_text="$(awk -v d="${delta_u}" 'BEGIN { printf "%.2f mWh", d / 1000.0 }')"
    rate_text="$(awk -v d="${delta_u}" -v s="${slept_seconds}" 'BEGIN { if (s > 0) printf "%.2f mW", (d / 1000.0) / (s / 3600.0); else printf "n/a"; }')"
  else
    return 0
  fi

  [[ -n "${before_src:-}" || -n "${after_src:-}" ]] && log_summary_row "power source" "${before_src:-?} -> ${after_src:-?}"
  log_summary_row "battery before" "${before_pct}%"
  log_summary_row "battery after"  "${after_pct}%"
  log_summary_row "battery delta"  "${delta_text}"
  log_summary_row "est sleep drain" "${rate_text}"
}

log_last_sleep_summary() {
  local entry_raw exit_raw entry_sec exit_sec start_iso exit_iso slept_seconds slept_text
  local error_matches raw_error_count error_buckets unique_error_count bucket_line n=0

  entry_raw="$(journalctl -b --no-pager -o short-unix 2>/dev/null | awk '/PM: suspend entry/ {ts=$1} END{print ts}')"
  exit_raw="$(journalctl -b --no-pager -o short-unix 2>/dev/null | awk '/PM: suspend exit/ {ts=$1} END{print ts}')"
  [[ -n "${entry_raw}" && -n "${exit_raw}" ]] || return 0

  entry_sec="${entry_raw%%.*}"; exit_sec="${exit_raw%%.*}"
  [[ "${entry_sec}" =~ ^[0-9]+$ && "${exit_sec}" =~ ^[0-9]+$ ]] || return 0
  (( exit_sec >= entry_sec )) || return 0

  start_iso="$(date --iso-8601=seconds -d "@${entry_sec}" 2>/dev/null || date -d "@${entry_sec}" '+%Y-%m-%dT%H:%M:%S%z')"
  exit_iso="$(date --iso-8601=seconds -d "@${exit_sec}" 2>/dev/null || date -d "@${exit_sec}" '+%Y-%m-%dT%H:%M:%S%z')"
  slept_seconds=$((exit_sec - entry_sec))
  printf -v slept_text '%02d:%02d:%02d' $((slept_seconds / 3600)) $(((slept_seconds % 3600) / 60)) $((slept_seconds % 60))

  error_matches="$(journalctl -b --no-pager -o short-iso --since "@${entry_sec}" 2>/dev/null \
    | rg -i '(\*ERROR\*|(^|[[:space:]])error([[:space:]:]|$)| failed| failure|timed out|timeout)' 2>/dev/null || true)"
  raw_error_count="$(printf '%s\n' "${error_matches}" | sed '/^$/d' | wc -l | tr -d ' ')"
  error_buckets="$(printf '%s\n' "${error_matches}" | sed '/^$/d' \
    | sed -E \
      -e 's/^[0-9T:+-]+ [^ ]+ [^:]+: //' \
      -e 's/[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]/PCI/gI' \
      -e 's/0x[0-9a-f]+/0xHEX/gI' \
      -e 's/usb[0-9]+/usbN/g' \
    | sort | uniq -c | sort -nr 2>/dev/null || true)"
  unique_error_count="$(printf '%s\n' "${error_buckets}" | sed '/^$/d' | wc -l | tr -d ' ')"

  log '+----------------------+---------------------------+'
  log_summary_row "suspend entered"  "${start_iso}"
  log_summary_row "suspend exited"   "${exit_iso}"
  log_summary_row "time asleep"      "${slept_text}"
  log_battery_summary "${slept_seconds}"
  log_summary_row "matched log lines"   "${raw_error_count}"
  log_summary_row "unique issue types"  "${unique_error_count}"
  log '+----------------------+---------------------------+'

  while IFS= read -r bucket_line; do
    [[ -n "${bucket_line}" ]] || continue
    ((n += 1))
    log "summary issue ${n}: ${bucket_line# }"
    (( n >= 3 )) && break
  done <<< "${error_buckets}"
}

log "resume worker: reloading BCE and WiFi"
sleep 1
modprobe apple-bce 2>/dev/null || true
udevadm settle -t 10 || true
modprobe brcmfmac 2>/dev/null || true
modprobe brcmfmac_wcc 2>/dev/null || true
log_last_sleep_summary
SCRIPT
chmod 755 /usr/local/libexec/t2-post-resume.sh
ok "t2-post-resume.sh criado"

# =============================================================================
section "8. Systemd services"
# =============================================================================

# disable-xhc2-wakeup.service
cat > /etc/systemd/system/disable-xhc2-wakeup.service << 'EOF'
[Unit]
Description=Disable spurious ACPI wakeup sources (T2 Mac)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/disable-wakeup-sources.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# suspend-fix-t2.service
cat > /etc/systemd/system/suspend-fix-t2.service << 'EOF'
[Unit]
Description=T2 Mac suspend/resume helper
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=20s
TimeoutStopSec=20s
ExecStart=/usr/local/libexec/t2-suspend-helper.sh pre
ExecStop=/usr/local/libexec/t2-suspend-helper.sh post

[Install]
WantedBy=sleep.target
EOF

# t2-post-resume.service
cat > /etc/systemd/system/t2-post-resume.service << 'EOF'
[Unit]
Description=T2 Mac post-resume recovery
After=systemd-suspend.service systemd-hybrid-sleep.service systemd-suspend-then-hibernate.service

[Service]
Type=oneshot
TimeoutStartSec=45s
ExecStart=/usr/local/libexec/t2-post-resume.sh

[Install]
WantedBy=sleep.target
EOF

systemctl daemon-reload
systemctl enable --now disable-xhc2-wakeup.service
systemctl enable suspend-fix-t2.service
systemctl enable t2-post-resume.service
ok "Services habilitados"

# =============================================================================
section "9. Aplicar configurações em runtime (sem reboot)"
# =============================================================================
# Desabilitar wakeup sources agora
/usr/local/libexec/disable-wakeup-sources.sh
ok "Wakeup sources ajustados agora"

# Recarregar logind
systemctl kill -s HUP systemd-logind 2>/dev/null || true
ok "systemd-logind recarregado"

# Recarregar udev
udevadm control --reload-rules && udevadm trigger --subsystem-match=pci 2>/dev/null || true
ok "udev rules recarregadas"

# =============================================================================
section "Verificação final"
# =============================================================================
echo
echo "  mem_sleep_default no GRUB:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | grep -o "mem_sleep_default=[^ \"]*" || echo "    (não encontrado)"

echo "  ACPI wakeup sources:"
awk 'NR>1 && $1!="" {printf "    %-8s %s  %s\n", $1, $3, $4}' /proc/acpi/wakeup | grep -v "^$"

echo "  Thunderbolt xHCI async:"
cat /sys/bus/pci/devices/0000:06:00.0/power/async 2>/dev/null && echo "    (ficheiro OK)" || echo "    (dispositivo não presente)"

echo "  Services:"
for svc in disable-xhc2-wakeup.service suspend-fix-t2.service t2-post-resume.service; do
    state=$(systemctl is-enabled "${svc}" 2>/dev/null || echo "não encontrado")
    printf "    %-40s %s\n" "${svc}" "${state}"
done

echo
ok "Setup concluído! Reinicie para o mem_sleep_default=s2idle entrar em efeito."
warn "Lembrete: para acordar de suspend, use o botão de power (comportamento normal no T2 com s2idle)."
