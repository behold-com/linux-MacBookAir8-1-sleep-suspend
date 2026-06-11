# setup-t2-suspend.sh

Configuration script for suspend/sleep on T2 MacBook Air (MacBookAir8,1/8,2) running Ubuntu 26.04 LTS with t2-resolute kernel.

## Compatible System

- **Hardware**: MacBook Air 2018/2019 (MacBookAir8,1 and MacBookAir8,2)
- **System**: Ubuntu 26.04 LTS
- **Kernel**: t2-resolute (patched kernel for Apple T2 support)

## Features

This script automatically configures the system for stable suspend/sleep on T2 Macs:

### 1. Kernel Configuration (GRUB)
- Sets `mem_sleep_default=s2idle` as kernel parameter
- Updates GRUB with the new configuration
- s2idle mode is required for T2 to work correctly

### 2. systemd Configuration (sleep.conf)
- Forces s2idle as suspend state
- Disables hibernation (not supported on T2)
- Disables hybrid sleep and suspend-then-hibernate

### 3. systemd Configuration (logind.conf)
- Configures lid switch behavior
- Sets idle action to ignore
- Suspend on lid close (with or without external power)

### 4. udev Rules for Thunderbolt
- Disables async resume on Thunderbolt xHCI controller
- Prevents -19 error during suspend/resume
- Applies specific PCI rules for T2

### 5. Wakeup Sources Disable Script
- Disables spurious wakeup sources (XHC2, RP01, RP05, RP09, ARPT)
- Prevents unwanted wake-ups during suspend
- Automatically executed at boot

### 6. Pre-Suspend Helper Script
- Saves battery state before suspending
- Removes kernel modules (BCE and WiFi) before suspend
- Prevents conflicts during suspend cycle

### 7. Post-Resume Helper Script
- Reloads BCE and WiFi modules after resume
- Generates detailed log of suspend/resume cycle
- Calculates battery drain during sleep
- Reports errors found in system logs

### 8. Systemd Services
- **disable-xhc2-wakeup.service**: Disables wakeup sources at boot
- **suspend-fix-t2.service**: Manages pre/post suspend hooks
- **t2-post-resume.service**: Executes post-resume recovery asynchronously

### 9. Immediate Application
- Applies configurations without immediate reboot
- Reloads udev rules and logind
- Adjusts wakeup sources at runtime

## Usage

Execute the script as root:

```bash
sudo bash ~/setup-t2-suspend.sh
```

After execution, **reboot the system** for GRUB changes to take effect.

## Important Warnings

### ⚠️ Potential Errors

1. **Thunderbolt -19 Error**: If -19 error occurs during suspend, verify that the udev rule was applied correctly and that `/sys/bus/pci/devices/0000:06:00.0/power/async` contains "disabled".

2. **Spurious Wake**: If the Mac wakes up by itself, check wakeup sources in `/proc/acpi/wakeup`. The script attempts to disable the main ones, but manual adjustment may be needed.

3. **WiFi Not Working After Resume**: If WiFi doesn't return after resume, check logs with `journalctl -u t2-post-resume.service` to identify the problem.

4. **Incompatible Hardware**: The script checks if hardware is MacBookAir8,1/8,2. If run on another model, it may not work correctly.

### ⚠️ T2-Specific Behavior

- **Waking from suspend**: Use the **power button** to wake. This is normal behavior on T2 with s2idle.
- **Keyboard/trackpad**: Do not work to wake from suspend on T2.
- **Hibernation**: Not supported and intentionally disabled.

## Verification

After execution, the script shows a summary of applied configurations:
- mem_sleep_default parameter in GRUB
- ACPI wakeup sources status
- Thunderbolt xHCI async status
- systemd services status

## Logs

Suspend/resume cycle logs can be checked with:

```bash
journalctl -u t2-post-resume.service
journalctl -u suspend-fix-t2.service
```

## Requirements

- `dmidecode` (for hardware verification)
- `rg` (ripgrep) for log analysis
- Root access (sudo)

## Support

This script was developed specifically for MacBook Air with T2 chip running Ubuntu 26.04 LTS with t2-resolute kernel. Other Ubuntu versions or distributions may require adjustments.
