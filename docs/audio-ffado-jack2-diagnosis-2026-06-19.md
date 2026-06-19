# Audio/FFADO Diagnosis: Saffire Pro 24 JACK2/FFADO Backend Stops After Xrun

Date: 2026-06-19, Europe/Lisbon  
Host: `deepthought`  
Reporter: local diagnostic session from `/home/wonko/projects/nix/WonkoOS`  
Issue: after switching from PipeWire/ALSA to JACK2/FFADO, Ardour cannot connect to JACK. JACK remains active under systemd, but its FFADO driver has stopped.

## Executive Summary

The current failure is no longer a PipeWire graph or WirePlumber routing problem. PipeWire and WirePlumber are disabled. JACK2 starts directly with the FFADO backend, FFADO enumerates the Focusrite Saffire Pro 24, and the expected realtime scheduling is present. After roughly 3.5 minutes, the FFADO backend reports an unhandled xrun and stops. The `jackd` process remains alive, so systemd still reports `jack.service` as active, but JACK clients can no longer connect.

Evidence:

- Booted generation is tagged `jack-ffado` and both `/run/current-system` and the system profile point to the same JACK/FFADO generation.
- `pipewire`, `wireplumber`, and `pipewire-pulse` system and user units are inactive.
- `jackd` starts as `jackaudio` with `-R -P 88 -dfirewire -r 48000 -p 2048 -n 3`.
- `ffado-test ListDevices` enumerates `Focusrite - SAFFIRE_PRO_24`, GUID `0x00130e0401c04de0`.
- FireWire IRQ threads are `SCHED_FIFO` priority 99 after the latest `rtirq` config.
- FFADO/JACK streaming threads are visible under `jackd`; key threads are `SCHED_FIFO` priorities 92-94.
- The failure sequence is direct from JACK/FFADO:
  - `JackFFADODriver::ffado_driver_wait - unhandled xrun`
  - `firewire ERR: wait status < 0! (= -1)`
  - `JackAudioDriver::ProcessAsync: read error, stopping...`
- After that, `jack_lsp` fails with `jack_client_open() failed, status = 0x21`.

Current working hypothesis: the remaining problem is below Ardour and below PipeWire. It is an FFADO/JACK/firewire streaming failure, likely involving FFADO DICE streaming, the FireWire controller path, period-size behavior, or a kernel/firewire transport condition. Missing realtime scheduling is now unlikely based on the observed priorities.

## Upstream Guidance Applied

This pass was based on the previous diagnosis document:

- `https://github.com/bhechinger/WonkoOS/blob/saffire-ffado/docs/audio-ffado-diagnosis-2026-06-18.md`

And Jonathan's FFADO mailing-list reply:

- `https://sourceforge.net/p/ffado/mailman/message/59348188/`

Jonathan's actionable points, paraphrased:

- Determine whether the same hardware and OS can run through `jackd`/FFADO.
- Determine whether FFADO's threads are running `SCHED_FIFO`.
- Try to obtain higher FFADO debug output, ideally level 5 or 6.
- Try period size 512, even if it is not expected to help.
- Test whether either of the two FW643 controllers behaves differently.
- If possible, remove or disable one FW643 controller and see whether symptoms change.
- Treat the boot-time `isochronous cycle inconsistent` message as probably spurious if it only appears before JACK/PipeWire/FFADO starts.
- FFADO 2.5.0 exists, but Jonathan did not expect it to change this specific result.

## Diagnostic Plan

The plan split into checks that can be run on the live system and checks that need a reboot or physical hardware change.

Live checks run in this session:

1. Confirm the booted JACK/FFADO generation.
2. Confirm PipeWire and WirePlumber are inactive.
3. Confirm JACK service arguments and environment.
4. Confirm FireWire controller topology and Saffire enumeration.
5. Confirm kernel FireWire messages and loaded modules.
6. Confirm FireWire IRQ realtime priority.
7. Confirm FFADO/JACK realtime thread priority.
8. Confirm JACK client failure after the FFADO backend stops.

Follow-up checks not run in this session:

1. Reboot into a controlled JACK run with FFADO verbose level 6.
2. Reboot or restart cleanly with period size 512 and the same verbose logging.
3. Move the Saffire between the two FW643 controllers and compare stability.
4. Physically remove or disable one FW643 controller, then test each remaining topology.
5. Only after those data points, consider testing FFADO 2.5.0 or adding a watchdog restart.

## System Details

```text
$ date -Is
2026-06-19T18:05:29+01:00

$ uname -a
Linux deepthought 7.0.12 #1-NixOS SMP PREEMPT_DYNAMIC Tue Jun  9 10:32:51 UTC 2026 x86_64 GNU/Linux

$ nixos-version
26.05.20260611.a037402 (Yarara)

$ readlink -f /run/current-system
/nix/store/ki049npqxdfgypmsdd62a985m12v7hwx-nixos-system-deepthought-jack-ffado-26.05.20260611.a037402

$ readlink -f /nix/var/nix/profiles/system
/nix/store/ki049npqxdfgypmsdd62a985m12v7hwx-nixos-system-deepthought-jack-ffado-26.05.20260611.a037402
```

JACK and FFADO versions:

```text
$ jackd --version
jackdmp version 1.9.22 tmpdir /dev/shm protocol 9

$ ffado-test ListDevices
FFADO test and diagnostic utility
Version: 2.4.9

=== 1394 PORT 0 ===
  Node id  GUID                  VendorId     ModelId   Vendor - Model
   1       0x00130e0401c04de0  0x0000130E  0x00000007   Focusrite - SAFFIRE_PRO_24
```

The JACK firewire backend exposes the needed debug knob:

```text
$ jackd -dfirewire --help
...
  -p, --period   Frames per period (default: 1024)
  -n, --nperiods Number of periods of playback latency (default: 3)
  -r, --rate     Sample rate (default: 48000)
  -v, --verbose  libffado verbose level (default: 3)
```

## Relevant Configuration

System JACK/FFADO config:

```text
$ sed -n '1,180p' systems/deepthought/audio.nix
let
  jackSampleRate = 48000;
  jackPeriodSize = 2048;
  jackPeriods = 3;
  jackRealtimePriority = 88;
in
{
  musnix = {
    enable = true;
    ffado.enable = true;
    soundcardPciId = "06:00.0";
    rtcqs.enable = true;
    rtirq = {
      resetAll = 1;
      prioLow = 0;
      enable = true;
      highList = "firewire_ohci";
      nameList = "rtc0";
    };
  };

  services = {
    pipewire = {
      enable = false;
      audio.enable = false;
      wireplumber.enable = false;
      alsa.enable = false;
      pulse.enable = false;
      jack.enable = false;
    };

    jack = {
      jackd = {
        enable = true;
        extraOptions = [
          "-R" "-P" "88" "-dfirewire" "-r" "48000" "-p" "2048" "-n" "3"
        ];
        session = lib.mkForce "";
      };
      alsa.enable = false;
      loopback.enable = false;
    };
  };

  systemd.services.jack = {
    after = [ "rtirq.service" ];
    wants = [ "rtirq.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.rtirq.after = lib.mkForce [ "sysinit.target" ];
}
```

Kernel FireWire config:

```text
$ sed -n '1,140p' systems/deepthought/system.nix
system.nixos.tags = [ "jack-ffado" ];
...
boot.initrd.kernelModules = [
  "firewire_ohci"
  "firewire_core"
];
...
boot.kernelModules = [
  "kvm-amd"
  "firewire-ohci"
];
boot.blacklistedKernelModules = [
  "snd_dice"
  "snd_fireworks"
];
boot.extraModprobeConfig = ''
  options firewire-ohci quirks=0x14
'';
```

Home audio packages include JACK tools and Ardour; `spotify-midi-control` is disabled:

```text
$ sed -n '1,160p' home/audio.nix
home.packages = with pkgs; [
  ardour
  carla
  ffado-mixer
  jack2
  jack-example-tools
  qjackctl
  ...
];

services.spotify-midi-control.enable = false;
```

## Hardware and Kernel State

FireWire controllers:

```text
$ lspci -nn
06:00.0 FireWire (IEEE 1394) [0c00]: LSI Corporation FW643 [TrueFire] PCIe 1394b Controller [11c1:5901] (rev 08)
07:00.0 FireWire (IEEE 1394) [0c00]: LSI Corporation FW643 [TrueFire] PCIe 1394b Controller [11c1:5901] (rev 08)
```

Controller details:

```text
$ lspci -vv -s 06:00.0
06:00.0 FireWire (IEEE 1394): LSI Corporation FW643 [TrueFire] PCIe 1394b Controller (rev 08) (prog-if 10 [OHCI])
  Subsystem: IOI Technology Corp FWB-PCIE1X2x
  Interrupts: pin B routed to IRQ 32
  Kernel driver in use: firewire_ohci

$ lspci -vv -s 07:00.0
07:00.0 FireWire (IEEE 1394): LSI Corporation FW643 [TrueFire] PCIe 1394b Controller (rev 08) (prog-if 10 [OHCI])
  Subsystem: IOI Technology Corp FWB-PCIE1X2x
  Interrupts: pin B routed to IRQ 39
  Kernel driver in use: firewire_ohci
```

Kernel FireWire messages:

```text
$ journalctl -k -b --no-pager | rg -i 'firewire|1394|ffado|dice|isochron|cycle|snd_dice|snd_fireworks|xrun'
Jun 19 17:55:01 kernel: firewire_ohci 0000:06:00.0: added OHCI v1.10 device as card 0, 8 IR + 8 IT contexts, quirks 0x14, physUB
Jun 19 17:55:01 kernel: firewire_ohci 0000:06:00.0: isochronous cycle inconsistent
Jun 19 17:55:01 kernel: firewire_ohci 0000:07:00.0: added OHCI v1.10 device as card 1, 8 IR + 8 IT contexts, quirks 0x14, physUB
Jun 19 17:55:02 kernel: firewire_core 0000:06:00.0: created device fw0: GUID 00027a16000139db, S800
Jun 19 17:55:02 kernel: firewire_core 0000:07:00.0: created device fw1: GUID 00027a16000139dc, S800
Jun 19 17:55:02 kernel: firewire_core 0000:06:00.0: created device fw2: GUID 00130e0401c04de0, S400
Jun 19 17:55:02 kernel: firewire_core 0000:06:00.0: phy config: new root=ffc1, gap_count=5
```

The `isochronous cycle inconsistent` message occurred during boot, before JACK started. It did not recur at the observed FFADO xrun time.

Loaded modules:

```text
$ lsmod | rg 'firewire|snd_dice|snd_firewire|snd_oxfw|snd_bebob|snd_fireworks|snd'
firewire_ohci          69632  0
firewire_core         258048  19 firewire_ohci
crc_itu_t              12288  1 firewire_core
...
```

No `snd_dice` or `snd_fireworks` module was loaded.

Device nodes:

```text
$ ls -l /dev/fw0 /dev/fw1 /dev/fw2 /dev/raw1394
ls: cannot access '/dev/raw1394': No such file or directory
crw------- 1 root root  246, 0 Jun 19 17:55 /dev/fw0
crw------- 1 root root  246, 1 Jun 19 17:55 /dev/fw1
crw-rw---- 1 root audio 246, 2 Jun 19 17:55 /dev/fw2
```

`/dev/fw2` is the Saffire node and is group-writable by `audio`. The old `/dev/raw1394` interface is absent.

## Service State

PipeWire and WirePlumber are inactive:

```text
$ systemctl is-active pipewire.service pipewire.socket wireplumber.service pipewire-pulse.service pipewire-pulse.socket jack.service rtirq.service
inactive
inactive
inactive
inactive
inactive
active
active

$ systemctl --user is-active pipewire.service pipewire.socket wireplumber.service pipewire-pulse.service pipewire-pulse.socket spotify-midi-control.service
inactive
inactive
inactive
inactive
inactive
inactive
```

JACK service:

```text
$ systemctl status jack.service --no-pager
Active: active (running) since Fri 2026-06-19 17:55:09 WEST
Main PID: 2480 (jackd)
CGroup: /system.slice/jack.service
  /nix/store/...-jack2-1.9.22/bin/jackd -R -P 88 -dfirewire -r 48000 -p 2048 -n 3
```

Systemd properties:

```text
$ systemctl show jack.service --property=ExecStart,Environment,LimitRTPRIO,LimitMEMLOCK,User,Restart
Restart=no
ExecStart=... jackd -R -P 88 -dfirewire -r 48000 -p 2048 -n 3
Environment=JACK_NO_AUDIO_RESERVATION=1 JACK_PROMISCUOUS_SERVER=jackaudio ...
LimitMEMLOCK=infinity
LimitRTPRIO=99
User=jackaudio
```

## Realtime and Scheduling State

`rtirq` correctly prioritised both FireWire controllers:

```text
$ systemctl status rtirq.service --no-pager
Setting IRQ high-priorities: start [firewire_ohci] pid=303 prio=99: OK.
Setting IRQ high-priorities: start [firewire_ohci] pid=304 prio=99: OK.
Setting IRQ high-priorities: start [firewire_ohci] pid=385 prio=99: OK.
Setting IRQ high-priorities: start [firewire_ohci] pid=386 prio=99: OK.
Setting IRQ priorities: start [rtc0] irq=8 pid=1413 prio=90: OK.
```

Observed thread priorities:

```text
$ ps -Leo pid,tid,cls,rtprio,pri,psr,comm,args | rg 'jackd|FW_|irq/.*firewire|qjackctl|ardour|ffado'
303   303  FF  99 139 11 irq/32-firewire [irq/32-firewire_ohci]
304   304  FF  99 139 11 irq/32-s-firewi [irq/32-s-firewire_ohci]
385   385  FF  99 139 13 irq/39-firewire [irq/39-firewire_ohci]
386   386  FF  99 139 13 irq/39-s-firewi [irq/39-s-firewire_ohci]
2480 2498  FF   1  41  0 jackd ... -dfirewire -r 48000 -p 2048 -n 3
2480 2509  FF  93 133  2 FW_ARMRT  ... -dfirewire -r 48000 -p 2048 -n 3
2480 2510  FF   1  41  9 FW_CTRHLP ... -dfirewire -r 48000 -p 2048 -n 3
2480 2511  FF  94 134 14 FW_ISOXMT ... -dfirewire -r 48000 -p 2048 -n 3
2480 2512  FF  92 132  9 FW_ISORCV ... -dfirewire -r 48000 -p 2048 -n 3
```

This directly answers the upstream scheduling question for the JACK case: FFADO threads are visible and the important streaming/control threads are running `SCHED_FIFO` with high realtime priority.

## JACK/FFADO Failure Timeline

Full relevant journal sequence:

```text
$ journalctl -u rtirq.service -u jack.service -u jack-session.service -b --no-pager
Jun 19 17:55:09 systemd[1]: Started JACK Audio Connection Kit.
Jun 19 17:55:09 jackd[2480]: jackdmp 1.9.22
Jun 19 17:55:09 jackd[2480]: JACK server starting in realtime mode with priority 88
Jun 19 17:55:09 jackd[2480]: self-connect-mode is "Don't restrict self connect requests"
Jun 19 17:55:09 jackd[2480]: ffado_streaming_init: libffado 2.4.9 built Jun 26 2024 09:44:00
Jun 19 17:55:10 jackd[2480]: Warning (dice_eap.cpp)[1811] read: No routes found. Base 0x7, offset 0x4000
Jun 19 17:55:10 jackd[2480]: Nick name        : Pro24-004de0
Jun 19 17:55:10 jackd[2480]: Clock Status     : locked 0x02
Jun 19 17:55:10 jackd[2480]: Samplerate       : 0x0000BB80 (48000)
Jun 19 17:55:10 jackd[2480]: setSamplingFrequency: Setting sample rate: 48000
Jun 19 17:55:11 jack-session-start[2492]: server is available
Jun 19 17:58:39 jackd[2480]: JackFFADODriver::ffado_driver_wait - unhandled xrun
Jun 19 17:58:39 jackd[2480]: firewire ERR: wait status < 0! (= -1)
Jun 19 17:58:39 jackd[2480]: JackAudioDriver::ProcessAsync: read error, stopping...
Jun 19 17:59:15 jackd[2480]: JackPosixProcessSync::LockedTimedWait error usec = 5000000 err = Connection timed out
Jun 19 17:59:15 jackd[2480]: Driver is not running
Jun 19 17:59:15 jackd[2480]: Cannot create new client
```

JACK client test after the failure:

```text
$ systemd-run --user --wait --collect --pipe env JACK_PROMISCUOUS_SERVER=jackaudio jack_lsp
Cannot read socket fd = 5 err = Success
CheckRes error
JackSocketClientChannel read fail
Cannot open lsp client
Error: cannot connect to JACK, jack_client_open() failed, status = 0x21
```

Interpretation: the `jackd` process remains alive, but the JACK driver is stopped. This is why `systemctl status jack.service` can look superficially healthy while Ardour cannot connect.

## Tests Run

| Test | Command | Status | Output / Notes |
|---|---|---:|---|
| Booted generation | `readlink -f /run/current-system` | PASS | Booted `...-nixos-system-deepthought-jack-ffado-26.05.20260611.a037402` |
| System profile | `readlink -f /nix/var/nix/profiles/system` | PASS | Matches `/run/current-system` |
| PipeWire disabled | `systemctl is-active ...` and `systemctl --user is-active ...` | PASS | PipeWire, WirePlumber, Pulse, and spotify MIDI control inactive |
| JACK service args | `systemctl show jack.service ...` | PASS | `jackd -R -P 88 -dfirewire -r 48000 -p 2048 -n 3` |
| FFADO enumeration | `ffado-test ListDevices` | PASS | Enumerated `Focusrite - SAFFIRE_PRO_24`, GUID `0x00130e0401c04de0` |
| FireWire modules | `lsmod | rg ...` | PASS | `firewire_ohci`/`firewire_core` loaded; `snd_dice`/`snd_fireworks` absent |
| FireWire IRQ priority | `rtirq.service` logs and `ps` | PASS | IRQ 32 and 39 FireWire threads at RT priority 99 |
| FFADO thread priority | `ps -Leo ... | rg 'FW_'` | PASS | `FW_ARMRT` 93, `FW_ISOXMT` 94, `FW_ISORCV` 92 |
| JACK/FFADO startup | `journalctl -u jack.service -b` | PASS | JACK starts and FFADO logs Saffire/DICE info |
| JACK/FFADO stability | `journalctl -u jack.service -b` | FAIL | `unhandled xrun`, `wait status < 0`, driver stops |
| JACK client after failure | `systemd-run --user ... jack_lsp` | FAIL | `jack_client_open() failed, status = 0x21` |
| Open device owner | `lsof /dev/fw2` | INCONCLUSIVE | Non-root invocation returned no rows after the driver had already failed |

## Findings

1. The same hardware and OS do not currently run successfully through JACK2/FFADO.

   This was one of Jonathan's most important questions. JACK/FFADO starts and enumerates the device, but the backend stops after an FFADO/firewire xrun. This makes the problem broader than PipeWire's FFADO integration.

2. FFADO's JACK threads are running with realtime scheduling.

   `FW_ARMRT`, `FW_ISOXMT`, and `FW_ISORCV` are `SCHED_FIFO` at priorities 93, 94, and 92. FireWire IRQ threads are priority 99. This does not rule out all scheduling problems, but it rules out the obvious "FFADO is not RT" failure mode.

3. The current boot-time `isochronous cycle inconsistent` message is probably not the direct trigger.

   It appears during kernel FireWire initialization at 17:55:01. JACK starts at 17:55:09 and fails at 17:58:39. No new `isochronous cycle inconsistent` message appears around the failure. This matches Jonathan's comment that a boot-only occurrence is probably spurious.

4. The failure leaves systemd with a false-positive service state.

   `jack.service` stays `active (running)` because the `jackd` process survives. Internally, JACK reports `Driver is not running` and refuses new clients.

5. The device and kernel ownership look correct enough for FFADO startup.

   `/dev/fw2` exists as `root:audio` `0660`, FFADO enumerates it, and JACK opens far enough to dump DICE device data and start streaming. This is not a simple missing permission or missing device-node issue.

6. The currently tested period is conservative but not the upstream-suggested experiment.

   The current config uses `2048/3`. Jonathan specifically suggested trying `512` to rule out systems that behave better at that period size. That test has not been run yet.

7. FFADO debug level is still insufficient for root cause.

   JACK's firewire backend supports `-v`. The current service uses the default libffado verbose level 3. The next useful log should be captured at level 6.

## Recommended Next Experiments

Run these in order, one variable at a time.

1. Controlled verbose JACK/FFADO boot

   Temporarily add `"-v" "6"` to the JACK firewire backend options, reboot into a clean state, wait for the failure, then collect:

   ```text
   journalctl -u rtirq.service -u jack.service -u jack-session.service -b --no-pager
   journalctl -k -b --no-pager | rg -i 'firewire|1394|isochron|cycle|xrun|irq'
   ps -Leo pid,tid,cls,rtprio,pri,psr,comm,args | rg 'jackd|FW_|irq/.*firewire'
   ```

   Goal: capture libffado debug around the first xrun rather than only JACK's final `wait status < 0`.

2. Period-size experiment at 512/3

   Change only the period size from 2048 to 512, keep sample rate 48000, periods 3, priority 88, and FFADO verbose level 6. Reboot and repeat the same capture.

   Goal: test Jonathan's buffer-size suggestion without mixing in other changes.

3. Controller A/B test

   Test the Saffire attached through each FW643 controller. For each controller, capture:

   ```text
   journalctl -k -b --no-pager | rg -i 'firewire|1394|fw[0-9]|isochron|cycle'
   ffado-test ListDevices
   journalctl -u jack.service -b --no-pager
   ```

   Goal: determine whether the xrun follows the Saffire regardless of controller or is specific to one FW643 path.

4. Single-controller test

   If physically practical, remove or disable one FW643 controller and test again. Then swap and test the other controller alone.

   Goal: rule out odd interactions from two identical FW643 controllers on the same PCIe switch path.

5. FFADO 2.5.0 test

   Only after the above, test FFADO 2.5.0 if packaging effort is acceptable. Jonathan noted its release but did not expect it to be decisive for this case.

6. Recovery watchdog

   A watchdog that restarts JACK when `jack_lsp` fails may improve usability, but it should not be treated as the primary fix until the FFADO/controller data above is collected.

## Mailing List Follow-up Draft

Subject idea: `JACK2/FFADO Saffire Pro 24: FFADO threads are RT, backend stops after unhandled xrun`

Follow-up summary:

I switched the same NixOS host from PipeWire FFADO to direct JACK2/FFADO to answer whether the Saffire works through `jackd` on the same PC/OS. It starts, FFADO enumerates the Saffire, and JACK initially becomes available. After about 3.5 minutes, the FFADO backend stops:

```text
Jun 19 17:58:39 jackd[2480]: JackFFADODriver::ffado_driver_wait - unhandled xrun
Jun 19 17:58:39 jackd[2480]: firewire ERR: wait status < 0! (= -1)
Jun 19 17:58:39 jackd[2480]: JackAudioDriver::ProcessAsync: read error, stopping...
```

After that, `jackd` remains running and systemd still reports `jack.service` active, but clients fail:

```text
Error: cannot connect to JACK, jack_client_open() failed, status = 0x21
```

Realtime scheduling now looks correct:

```text
irq/32-firewire_ohci  SCHED_FIFO 99
irq/39-firewire_ohci  SCHED_FIFO 99
FW_ARMRT              SCHED_FIFO 93
FW_ISOXMT             SCHED_FIFO 94
FW_ISORCV             SCHED_FIFO 92
```

Current JACK command:

```text
jackd -R -P 88 -dfirewire -r 48000 -p 2048 -n 3
```

The boot-only kernel message still appears:

```text
firewire_ohci 0000:06:00.0: isochronous cycle inconsistent
```

It occurs before JACK starts and does not recur at the xrun time.

Next planned tests are `-v 6` libffado logging, then `-p 512 -n 3`, then testing the two FW643 controllers separately.
