# Audio/FFADO Diagnosis: Saffire Pro 24 Hung After ALSA to FFADO Switch

Date: 2026-06-18, Europe/Lisbon  
Host: `deepthought`  
Reporter: local diagnostic session from `/home/wonko/projects/nix/WonkoOS`  
Issue: after switching the Focusrite Saffire Pro 24 from PipeWire ALSA FireWire nodes to PipeWire FFADO, audio appears hung. Ardour meters do not move.

## Executive Summary

The PipeWire graph and WirePlumber routing are present and internally consistent, but the FFADO-backed driver appears to stop delivering audio frames after startup.

Evidence:

- PipeWire starts `libpipewire-module-ffado-driver` and FFADO detects the device as `Focusrite - SAFFIRE_PRO_24`, GUID `0x00130e0401c04de0`.
- The FFADO nodes exist: `saffire_ffado_output` and `saffire_ffado_input`.
- Ardour is running as a PipeWire JACK client and is linked to the Saffire ports.
- Repository tests for FFADO config, live aliases, readiness, and routing all pass.
- PipeWire logs show repeated `mod.ffado-driver: Xrun ...` messages beginning shortly after Ardour starts, followed by `mod.ffado-driver: FFADO error`.
- After the FFADO error, `pw-top` still reports the Saffire and Ardour nodes as running, but every node shows `QUANT 0`, `WAIT 0.0us`, and no useful timing activity.
- A direct `pw-record` from `saffire_ffado_input` for six seconds created only a 44-byte WAV header. No audio frames were written.

Current working hypothesis: this is not a missing WirePlumber link or Ardour routing problem. PipeWire's FFADO driver creates the graph and ports, but the FFADO/PipeWire driver cycle fails shortly after startup and then leaves visible, running nodes that no longer process audio.

## System Details

```text
$ date -Is
2026-06-18T10:10:05+01:00

$ uname -a
Linux deepthought 7.0.12 #1-NixOS SMP PREEMPT_DYNAMIC Tue Jun  9 10:32:51 UTC 2026 x86_64 GNU/Linux

$ nixos-version
26.05.20260611.a037402 (Yarara)

$ readlink /run/current-system
/nix/store/ba9j74z0d20iwxqb0x84d58sl60qz2m2-nixos-system-deepthought-26.05.20260611.a037402

$ readlink /run/booted-system
/nix/store/ba9j74z0d20iwxqb0x84d58sl60qz2m2-nixos-system-deepthought-26.05.20260611.a037402
```

PipeWire/WirePlumber versions observed in `wpctl status`:

```text
PipeWire 'pipewire-0' [1.6.5, wonko@deepthought, cookie:1747701265]
WirePlumber [1.6.5, wonko@deepthought, pid:2581]
pipewire-pulse [1.6.5, wonko@deepthought, pid:2585]
```

FFADO version:

```text
$ ffado-diag
FFADO diagnostic utility 2.4.9
...
kernel version            7.0.12
Preempt (low latency)     False
RT patched                False
...
uname -a                  Linux deepthought 7.0.12 #1-NixOS SMP PREEMPT_DYNAMIC Tue Jun  9 10:32:51 UTC 2026 x86_64 GNU/Linux
```

Note: `ffado-diag` exits nonzero in this environment and prints `/dev/fw* []`, while `ffado-test ListDevices` does enumerate the Saffire. The device node exists and PipeWire has it open.

## Relevant Configuration

FFADO module fragment:

```text
$ sed -n '1,220p' home/pipewire/saffire-ffado.conf
context.modules = [
  {
    name = libpipewire-module-ffado-driver
    args = {
      driver.mode = duplex
      ffado.devices = [ "hw:0" ]
      ffado.period-size = 1024
      ffado.period-num = 3
      ffado.sample-rate = 48000
      ffado.realtime = true
      ffado.rtprio = 93
      sink.props = {
        node.name = "saffire_ffado_output"
        node.description = "Saffire Pro 24 FFADO Output"
        priority.driver = 4000
        priority.session = 4000
      }
      source.props = {
        node.name = "saffire_ffado_input"
        node.description = "Saffire Pro 24 FFADO Input"
        priority.driver = 200
        priority.session = 200
      }
    }
    flags = [ ifexists nofail ]
  }
]
```

System-level audio/RT config:

```text
$ sed -n '1,140p' systems/deepthought/audio.nix
{
  pkgs,
  ...
}:

{
  security.rtkit.enable = true;

  musnix = {
    enable = true;
    ffado.enable = true;
    soundcardPciId = "06:00.0";
    rtcqs.enable = true;
    rtirq = {
      resetAll = 1;
      prioLow = 0;
      enable = true;
      nameList = "rtc0 firewire_ohci";
    };
  };

  services = {
    pipewire = {
      enable = true;
      audio.enable = true;
      wireplumber.enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;
      socketActivation = true;
    };
  };

  systemd.user.services = {
    pipewire.serviceConfig = {
      LimitMEMLOCK = "infinity";
      LimitRTPRIO = 95;
      LimitNICE = "-11";
      RestrictRealtime = false;
    };
    pipewire-pulse.serviceConfig = {
      LimitMEMLOCK = "infinity";
      LimitRTPRIO = 95;
      LimitNICE = "-11";
      RestrictRealtime = false;
    };
    wireplumber.serviceConfig = {
      LimitMEMLOCK = "infinity";
      LimitRTPRIO = 95;
      LimitNICE = "-11";
      RestrictRealtime = false;
    };
  };

  systemd.services."user@".serviceConfig = {
    LimitMEMLOCK = "infinity";
    LimitRTPRIO = 95;
    LimitNICE = "-11";
    RestrictRealtime = false;
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
    alsa-lib
    pulseaudioFull
  ];
}
```

Kernel FireWire config:

```text
$ sed -n '1,90p' systems/deepthought/system.nix
...
    kernelModules = [
      "kvm-amd"
      "firewire-ohci"
    ];
    blacklistedKernelModules = [
      "snd_dice"
      "snd_fireworks"
    ];
    extraModprobeConfig = ''
      options firewire-ohci quirks=0x14
    '';
...
```

Ardour readiness checks require the FFADO nodes and live port aliases. The readiness helper passed before Ardour started:

```text
Jun 18 09:57:27 deepthought ardour-pipewire-ready[3866]: ardour-pipewire-ready: PipeWire Saffire audio and MIDI ports are ready
```

## Hardware and Kernel State

```text
$ lspci -nn | rg -i 'firewire|1394|audio|06:00|07:00'
06:00.0 FireWire (IEEE 1394) [0c00]: LSI Corporation FW643 [TrueFire] PCIe 1394b Controller [11c1:5901] (rev 08)
07:00.0 FireWire (IEEE 1394) [0c00]: LSI Corporation FW643 [TrueFire] PCIe 1394b Controller [11c1:5901] (rev 08)
0a:00.1 Audio device [0403]: NVIDIA Corporation GA102 High Definition Audio Controller [10de:1aef] (rev a1)
0c:00.4 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse HD Audio Controller [1022:1487]
```

FireWire boot messages:

```text
$ journalctl -k -b --no-pager | rg -i 'firewire|ffado|dice|ohci|snd|irq|xrun|isochron'
Jun 18 09:56:43 deepthought kernel: firewire_ohci 0000:06:00.0: enabling device (0000 -> 0002)
Jun 18 09:56:43 deepthought kernel: firewire_ohci 0000:06:00.0: added OHCI v1.10 device as card 0, 8 IR + 8 IT contexts, quirks 0x14, physUB
Jun 18 09:56:43 deepthought kernel: firewire_ohci 0000:07:00.0: enabling device (0000 -> 0002)
Jun 18 09:56:43 deepthought kernel: firewire_ohci 0000:06:00.0: isochronous cycle inconsistent
Jun 18 09:56:43 deepthought kernel: firewire_ohci 0000:07:00.0: added OHCI v1.10 device as card 1, 8 IR + 8 IT contexts, quirks 0x14, physUB
Jun 18 09:56:44 deepthought kernel: firewire_core 0000:06:00.0: created device fw0: GUID 00027a16000139db, S800, quirks 00000000
Jun 18 09:56:44 deepthought kernel: firewire_core 0000:07:00.0: created device fw1: GUID 00027a16000139dc, S800, quirks 00000000
Jun 18 09:56:44 deepthought kernel: firewire_core 0000:06:00.0: created device fw2: GUID 00130e0401c04de0, S400, quirks 00000000
Jun 18 09:56:44 deepthought kernel: firewire_core 0000:06:00.0: phy config: new root=ffc1, gap_count=5
```

Loaded modules:

```text
$ lsmod | rg 'firewire|snd_dice|snd_firewire|snd_oxfw|snd_bebob|snd_fireworks|snd'
...
firewire_ohci          69632  0
firewire_core         258048  19 firewire_ohci
crc_itu_t              12288  1 firewire_core
```

No `snd_dice` or `snd_fireworks` module was loaded.

Device nodes:

```text
$ ls -l /dev/fw0 /dev/fw1 /dev/fw2
crw-------  1 root root  246, 0 Jun 18 09:56 /dev/fw0
crw-------  1 root root  246, 1 Jun 18 09:56 /dev/fw1
crw-rw----+ 1 root audio 246, 2 Jun 18 09:57 /dev/fw2
```

Open FireWire device handles:

```text
$ lsof /dev/fw2
COMMAND   PID  USER  FD   TYPE DEVICE SIZE/OFF NODE NAME
pipewire 2579 wonko mem    CHR  246,2           243 /dev/fw2
pipewire 2579 wonko 129u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 134u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 139u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 144u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 149u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 153u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 154u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 159u   CHR  246,2      0t0  243 /dev/fw2
pipewire 2579 wonko 161u   CHR  246,2      0t0  243 /dev/fw2
```

FFADO device enumeration:

```text
$ timeout 5 ffado-test ListDevices
no message buffer overruns
-----------------------------------------------
FFADO test and diagnostic utility
Part of the FFADO project -- www.ffado.org
Version: 2.4.9
(C) 2008-2021, Daniel Wagner, Pieter Palmers and others
This program comes with ABSOLUTELY NO WARRANTY.
-----------------------------------------------

=== 1394 PORT 0 ===
  Node id  GUID                  VendorId     ModelId   Vendor - Model
   1       0x00130e0401c04de0  0x0000130E  0x00000007   Focusrite - SAFFIRE_PRO_24
```

## Realtime and Scheduling State

```text
$ id
uid=1000(wonko) gid=100(users) groups=100(users),65534(nogroup)

$ ulimit -r
99

$ systemctl --user show pipewire.service -p LimitRTPRIO -p LimitMEMLOCK -p LimitNICE -p RestrictRealtime -p ExecStart
ExecStart={ path=/nix/store/m2kqwy3rb25dy5zi5sjl4f6raryb67y9-pipewire-1.6.5/bin/pipewire ; argv[]=/nix/store/m2kqwy3rb25dy5zi5sjl4f6raryb67y9-pipewire-1.6.5/bin/pipewire ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }
LimitMEMLOCK=infinity
LimitNICE=31
LimitRTPRIO=95
RestrictRealtime=no

$ ps -Leo pid,tid,cls,rtprio,pri,ni,comm | rg 'pipewire|wireplumber|irq/32|irq/39|Ardour|ardour'
    297     297  FF     51  91   - irq/32-firewire_ohci
    298     298  FF     50  90   - irq/32-s-firewire_ohci
    387     387  FF     51  91   - irq/39-firewire_ohci
    388     388  FF     50  90   - irq/39-s-firewire_ohci
   2579    2579  TS      -  30 -11 pipewire
   2579    2601  FF      1  41   - pipewire
   2581    2581  TS      -  30 -11 wireplumber
   2581    2669  TS      -  30 -11 wireplumber-ust
   2581    2670  TS      -  30 -11 wireplumber-ust
   2585    2585  TS      -  30 -11 pipewire-pulse
   5993    5993  TS      -  19   0 ArdourGUI
   5993    6550  TS      -  19   0 pw-ardour
   5993    6551  TS      -  19   0 pw-ardour
   5993    8631  TS      -  19   0 ArdourGUI
```

Observation: the PipeWire thread shown in `SCHED_FIFO` is only RT priority 1, even though the FFADO config says `ffado.rtprio = 93` and the systemd limit allows RT priority 95. The FireWire IRQ threads are RT priority 51.

## Service State

```text
$ systemctl --user status pipewire.service
● pipewire.service - PipeWire Multimedia Service
     Loaded: loaded (/home/wonko/.config/systemd/user/pipewire.service; enabled; preset: ignored)
     Active: active (running) since Thu 2026-06-18 09:56:52 WEST; 13min ago
   Main PID: 2579 (pipewire)
...
Jun 18 09:59:39 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:15 PipeWire:15 source:1 sink:1
Jun 18 09:59:47 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:16 PipeWire:16 source:1 sink:1
Jun 18 10:00:04 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:17 PipeWire:17 source:1 sink:1
Jun 18 10:00:13 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:18 PipeWire:18 source:1 sink:1
Jun 18 10:00:21 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:19 PipeWire:19 source:1 sink:1
Jun 18 10:00:29 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:20 PipeWire:20 source:1 sink:1
Jun 18 10:00:37 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:21 PipeWire:21 source:1 sink:1
Jun 18 10:00:45 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:22 PipeWire:22 source:1 sink:1
Jun 18 10:00:53 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:23 PipeWire:23 source:1 sink:1
Jun 18 10:01:07 deepthought pipewire[2579]: mod.ffado-driver: FFADO error
```

```text
$ systemctl --user status wireplumber.service
● wireplumber.service - Multimedia Service Session Manager
     Active: active (running) since Thu 2026-06-18 09:56:52 WEST; 13min ago
...
Jun 18 09:57:22 deepthought wireplumber[2581]: default: Failed to get percentage from UPower: org.freedesktop.DBus.Error.NameHasNoOwner
Jun 18 09:57:22 deepthought wireplumber[2581]: spa.bluez5: BlueZ system service is not available
```

```text
$ systemctl --user status ardour-default.service
● ardour-default.service - Ardour Default session
     Active: active (running) since Thu 2026-06-18 09:57:27 WEST; 13min ago
    Process: 3866 ExecStartPre=/nix/store/4i3viajkbv1p1s8shrzp2zrmpzf62vq3-ardour-pipewire-ready/bin/ardour-pipewire-ready (code=exited, status=0/SUCCESS)
   Main PID: 5993 (ArdourGUI)
...
Jun 18 09:57:28 deepthought ardour9[5993]: Ardour: [INFO]: Detecting Audio/MIDI Devices
Jun 18 09:57:33 deepthought ardour9[5993]: Set cursor set to default
```

## PipeWire Graph State

`wpctl status` sees the Saffire FFADO source/sink and Ardour client:

```text
$ wpctl status
PipeWire 'pipewire-0' [1.6.5, wonko@deepthought, cookie:1747701265]
...
Audio
 ├─ Devices:
 │      66. GA102 High Definition Audio Controller [alsa]
 │      67. Camera                              [alsa]
 │      68. Starship/Matisse HD Audio Controller [alsa]
 │  
 ├─ Sinks:
 │  *   33. System Sounds                       [vol: 0.92]
 │      34. Games                               [vol: 1.00]
 │      35. Music                               [vol: 1.00]
 │      44. Saffire Pro 24 FFADO Output         [vol: 1.00]
 │      78. GA102 High Definition Audio Controller Digital Stereo (HDMI) [vol: 1.00]
 │  
 ├─ Sources:
 │  *   36. Ardour                              [vol: 1.00]
 │      45. Saffire Pro 24 FFADO Input          [vol: 1.00]
 │      79. Camera Mono                         [vol: 1.00]
```

Filtered node properties:

```text
$ timeout 5 pw-dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and (.info.props["node.name"] | test("saffire|ardour|Dummy|Freewheel"))) | {id, type, info: {state: .info.state, error: .info.error, props: .info.props, params: .info.params}}'
{
  "id": 44,
  "type": "PipeWire:Interface:Node",
  "info": {
    "state": "running",
    "error": null,
    "props": {
      "client.id": 41,
      "media.class": "Audio/Sink",
      "media.name": "FFADO Sink",
      "node.description": "Saffire Pro 24 FFADO Output",
      "node.driver": true,
      "node.group": "ffado-group",
      "node.loop.name": "data-loop.0",
      "node.name": "saffire_ffado_output",
      "node.pause-on-idle": false,
      "node.virtual": true,
      "node.want-driver": true,
      "object.id": 44,
      "object.serial": 45,
      "priority.driver": 4000,
      "priority.session": 4000
    }
  }
}
{
  "id": 45,
  "type": "PipeWire:Interface:Node",
  "info": {
    "state": "running",
    "error": null,
    "props": {
      "client.id": 41,
      "media.class": "Audio/Source",
      "media.name": "FFADO Source",
      "node.description": "Saffire Pro 24 FFADO Input",
      "node.driver": true,
      "node.driver-id": 44,
      "node.group": "ffado-group",
      "node.loop.name": "data-loop.0",
      "node.name": "saffire_ffado_input",
      "node.pause-on-idle": false,
      "node.virtual": true,
      "node.want-driver": true,
      "object.id": 45,
      "object.serial": 46,
      "priority.driver": 200,
      "priority.session": 200
    }
  }
}
{
  "id": 129,
  "type": "PipeWire:Interface:Node",
  "info": {
    "state": "running",
    "error": null,
    "props": {
      "client.api": "jack",
      "client.id": 130,
      "client.name": "ardour",
      "config.name": "jack.conf",
      "media.category": "Duplex",
      "media.role": "DSP",
      "media.type": "Audio",
      "node.always-process": true,
      "node.description": "ardour",
      "node.driver-id": 44,
      "node.group": "group.dsp.0",
      "node.lock-quantum": true,
      "node.name": "ardour",
      "node.transport.sync": true,
      "object.id": 129,
      "object.serial": 167
    }
  }
}
```

Ports exist:

```text
$ timeout 5 pw-link -io
saffire_ffado_output:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in
saffire_ffado_output:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in
...
saffire_ffado_input:00130e0401c04de0_1394/Out:01 (Anlg/In:03)_out
saffire_ffado_input:00130e0401c04de0_1394/Out:05 (SPDIF/In:01)_out
saffire_ffado_input:00130e0401c04de0_1394/Out:06 (SPDIF/In:02)_out
...
ardour:Master/audio_out 1
ardour:Master/audio_out 2
ardour:Mic/audio_in 1
ardour:Mac/audio_in 1
ardour:Mac/audio_in 2
```

Links exist:

```text
$ timeout 5 pw-link -l
saffire_ffado_output:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in
  |<- ardour:Click/audio_out 1
  |<- ardour:auditioner/audio_out 1
  |<- ardour:Master/audio_out 1
saffire_ffado_output:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in
  |<- ardour:Click/audio_out 2
  |<- ardour:auditioner/audio_out 2
  |<- ardour:Master/audio_out 2
saffire_ffado_input:00130e0401c04de0_1394/Out:01 (Anlg/In:03)_out
  |-> ardour:physical_audio_input_monitor_enable
  |-> ardour:Mic/audio_in 1
saffire_ffado_input:00130e0401c04de0_1394/Out:05 (SPDIF/In:01)_out
  |-> ardour:physical_audio_input_monitor_enable
  |-> ardour:Mac/audio_in 1
saffire_ffado_input:00130e0401c04de0_1394/Out:06 (SPDIF/In:02)_out
  |-> ardour:physical_audio_input_monitor_enable
  |-> ardour:Mac/audio_in 2
```

Link objects were active with no link-level error:

```text
$ timeout 5 pw-dump | jq -r '.[] | select(.type == "PipeWire:Interface:Link") | {id, state: .info.state, error: .info.error, props: .info.props}'
...
{
  "id": 223,
  "state": "active",
  "error": null,
  "props": {
    "factory.id": 21,
    "link.input.node": 44,
    "link.input.port": 80,
    "link.output.node": 129,
    "link.output.port": 173,
    "node.description": "static WirePlumber audio link",
    "object.id": 223,
    "object.linger": true,
    "object.serial": 289
  }
}
{
  "id": 225,
  "state": "active",
  "error": null,
  "props": {
    "factory.id": 21,
    "link.input.node": 129,
    "link.input.port": 175,
    "link.output.node": 45,
    "link.output.port": 89,
    "node.description": "static WirePlumber audio link",
    "object.id": 225,
    "object.linger": true,
    "object.serial": 291
  }
}
```

## Runtime Failure Indicators

`pw-top` after the FFADO error:

```text
$ timeout 5 pw-top -b
S   ID  QUANT   RATE    WAIT    BUSY   W/Q   B/Q  ERR FORMAT           NAME 
C   31      0      0    ---     ---   ---   ---     0                  Dummy-Driver
C   32      0      0    ---     ---   ---   ---     0                  Freewheel-Driver
C   33      0      0    ---     ---   ---   ---     0                  System Sounds
C   34      0      0    ---     ---   ---   ---     0                  Games
C   35      0      0    ---     ---   ---   ---     0                  Music
C   36      0      0    ---     ---   ---   ---     0                  Ardour
C   44      0      0    ---     ---   ---   ---     0                  saffire_ffado_output
C   45      0      0    ---     ---   ---   ---     0                  saffire_ffado_input
C  129      0      0    ---     ---   ---   ---     0                  ardour

S   ID  QUANT   RATE    WAIT    BUSY   W/Q   B/Q  ERR FORMAT           NAME 
R   44      0      0   0.0us   0.0us  ???   ???     0     F32P 8 48000 saffire_ffado_output
R   45      0      0   0.0us   0.0us  ???   ???     0    F32P 16 48000 saffire_ffado_input
R  129      0      0   0.0us   0.0us  ???   ???     0                  ardour
```

This is consistent across samples: nodes exist and are marked running, but there is no observable graph timing.

Direct capture test:

```text
$ timeout 6 pw-record --target saffire_ffado_input --rate 48000 --channels 1 /tmp/saffire-input-test.wav
/tmp/saffire-input-test.wav

$ stat -c '%n size=%s bytes mode=%A owner=%U group=%G' /tmp/saffire-input-test.wav
/tmp/saffire-input-test.wav size=44 bytes mode=-rw-r--r-- owner=wonko group=users

$ file /tmp/saffire-input-test.wav
/tmp/saffire-input-test.wav: RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 48000 Hz
```

Interpretation: only the WAV header was written. During the six-second capture window, no audio frames were received from `saffire_ffado_input`.

## PipeWire FFADO Log Timeline

Full relevant `pipewire.service` log from the current session:

```text
$ journalctl --user -u pipewire.service --since '2026-06-18 09:50:00' --no-pager
Jun 18 09:54:59 deepthought systemd[2384]: Stopping PipeWire Multimedia Service...
Jun 18 09:54:59 deepthought systemd[2384]: Stopped PipeWire Multimedia Service.
Jun 18 09:54:59 deepthought systemd[2384]: pipewire.service: Consumed 5min 27.660s CPU time over 8h 23min 23.459s wall clock time, 38.2M memory peak.
-- Boot 74fe6dddf4944c08893fd7ed3fa2608a --
Jun 18 09:55:27 deepthought systemd[2362]: Started PipeWire Multimedia Service.
Jun 18 09:56:19 deepthought systemd[2362]: Stopping PipeWire Multimedia Service...
Jun 18 09:56:19 deepthought systemd[2362]: Stopped PipeWire Multimedia Service.
-- Boot e01521ba66ab4a80bc1406735d060adc --
Jun 18 09:56:52 deepthought systemd[2380]: Started PipeWire Multimedia Service.
Jun 18 09:56:52 deepthought pipewire[2579]: 1781773012080352:  (ffado.cpp)[  92] ffado_streaming_init: libffado 2.4.9 built Jun 26 2024 09:44:00
Jun 18 09:56:52 deepthought pipewire[2579]: 00008870757: Warning (dice_eap.cpp)[1811] read: No routes found. Base 0x7, offset 0x4000
Jun 18 09:56:52 deepthought pipewire[2579]: 00008902078:  (dice_avdevice.cpp)[ 714] showDevice:  DICE Parameter Space info:
Jun 18 09:56:52 deepthought pipewire[2579]: 00008904237:  (dice_avdevice.cpp)[ 726] showDevice:   Owner            : 0x00000000FFFF0000
Jun 18 09:56:52 deepthought pipewire[2579]: 00008908679:  (dice_avdevice.cpp)[ 732] showDevice:   Nick name        : Pro24-004de0
Jun 18 09:56:52 deepthought pipewire[2579]: 00008910311:  (dice_avdevice.cpp)[ 735] showDevice:   Clock Select     : 0x02 0x0C
Jun 18 09:56:52 deepthought pipewire[2579]: 00008911684:  (dice_avdevice.cpp)[ 739] showDevice:   Enable           : false
Jun 18 09:56:52 deepthought pipewire[2579]: 00008913557:  (dice_avdevice.cpp)[ 743] showDevice:   Clock Status     : locked 0x02
Jun 18 09:56:52 deepthought pipewire[2579]: 00008916591:  (dice_avdevice.cpp)[ 750] showDevice:   Samplerate       : 0x0000BB80 (48000)
Jun 18 09:56:52 deepthought pipewire[2579]: 00008925296:  (dice_avdevice.cpp)[ 783] showDevice:    ISO channel       :  -1
Jun 18 09:56:52 deepthought pipewire[2579]: 00008928339:  (dice_avdevice.cpp)[ 788] showDevice:    Nb audio channels :  16
Jun 18 09:56:52 deepthought pipewire[2579]: 00008939467:  (dice_avdevice.cpp)[ 818] showDevice:    Nb audio channels :   8
Jun 18 09:56:52 deepthought pipewire[2579]: 00008959468:  (dice_avdevice.cpp)[ 324] setSamplingFrequency: Setting sample rate: 48000
Jun 18 09:57:28 deepthought pipewire[2579]: 00045193679:  (ffado.cpp)[  92] ffado_streaming_init: libffado 2.4.9 built Jun 26 2024 09:44:00
Jun 18 09:57:28 deepthought pipewire[2579]: 00045367863: Warning (dice_eap.cpp)[1811] read: No routes found. Base 0x7, offset 0x4000
Jun 18 09:57:28 deepthought pipewire[2579]: 00045408605:  (dice_avdevice.cpp)[ 732] showDevice:   Nick name        : Pro24-004de0
Jun 18 09:57:28 deepthought pipewire[2579]: 00045410066:  (dice_avdevice.cpp)[ 735] showDevice:   Clock Select     : 0x02 0x0C
Jun 18 09:57:28 deepthought pipewire[2579]: 00045411649:  (dice_avdevice.cpp)[ 739] showDevice:   Enable           : false
Jun 18 09:57:28 deepthought pipewire[2579]: 00045413048:  (dice_avdevice.cpp)[ 743] showDevice:   Clock Status     : locked 0x02
Jun 18 09:57:28 deepthought pipewire[2579]: 00045416598:  (dice_avdevice.cpp)[ 750] showDevice:   Samplerate       : 0x0000BB80 (48000)
Jun 18 09:57:28 deepthought pipewire[2579]: 00045425056:  (dice_avdevice.cpp)[ 783] showDevice:    ISO channel       :  -1
Jun 18 09:57:28 deepthought pipewire[2579]: 00045429025:  (dice_avdevice.cpp)[ 788] showDevice:    Nb audio channels :  16
Jun 18 09:57:28 deepthought pipewire[2579]: 00045440395:  (dice_avdevice.cpp)[ 818] showDevice:    Nb audio channels :   8
Jun 18 09:57:28 deepthought pipewire[2579]: 00045470679:  (dice_avdevice.cpp)[ 324] setSamplingFrequency: Setting sample rate: 48000
Jun 18 09:57:39 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:1 PipeWire:1 source:1 sink:1
Jun 18 09:57:48 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:2 PipeWire:2 source:1 sink:1
Jun 18 09:57:56 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:3 PipeWire:3 source:1 sink:1
Jun 18 09:58:03 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:4 PipeWire:4 source:1 sink:1
Jun 18 09:58:12 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:5 PipeWire:5 source:1 sink:1
Jun 18 09:58:20 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:6 PipeWire:6 source:1 sink:1
Jun 18 09:58:28 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:7 PipeWire:7 source:1 sink:1
Jun 18 09:58:43 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:8 PipeWire:8 source:1 sink:1
Jun 18 09:58:51 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:9 PipeWire:9 source:1 sink:1
Jun 18 09:58:59 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:10 PipeWire:10 source:1 sink:1
Jun 18 09:59:07 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:11 PipeWire:11 source:1 sink:1
Jun 18 09:59:15 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:12 PipeWire:12 source:1 sink:1
Jun 18 09:59:23 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:13 PipeWire:13 source:1 sink:1
Jun 18 09:59:31 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:14 PipeWire:14 source:1 sink:1
Jun 18 09:59:39 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:15 PipeWire:15 source:1 sink:1
Jun 18 09:59:47 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:16 PipeWire:16 source:1 sink:1
Jun 18 10:00:04 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:17 PipeWire:17 source:1 sink:1
Jun 18 10:00:13 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:18 PipeWire:18 source:1 sink:1
Jun 18 10:00:21 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:19 PipeWire:19 source:1 sink:1
Jun 18 10:00:29 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:20 PipeWire:20 source:1 sink:1
Jun 18 10:00:37 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:21 PipeWire:21 source:1 sink:1
Jun 18 10:00:45 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:22 PipeWire:22 source:1 sink:1
Jun 18 10:00:53 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:23 PipeWire:23 source:1 sink:1
Jun 18 10:01:07 deepthought pipewire[2579]: mod.ffado-driver: FFADO error
```

The full log contains duplicate DICE parameter dumps at 09:56:52 and 09:57:28. The important details are:

- Device nickname: `Pro24-004de0`
- Clock status: locked
- Sample rate: 48000
- TX channels: 16 audio, 1 MIDI
- RX channels: 8 audio, 1 MIDI
- ISO channel shown as `-1` in the DICE dump before streaming allocation
- Repeated xruns start at 09:57:39
- Terminal FFADO error at 10:01:07

## Tests Run

| Test | Command | Status | Output / Notes |
|---|---|---:|---|
| Repo readiness test | `sh tests/audio-readiness.sh` | PASS | `audio-readiness: ok` |
| Repo FFADO config test | `sh tests/saffire-ffado-config.sh` | PASS | `saffire-ffado-config: ok` |
| Repo live alias test | `sh tests/saffire-ffado-live-aliases.sh` | PASS | `saffire-ffado-live-aliases: ok` |
| Repo routing reconciler test | `sh tests/audio-routes-reconcile.sh` | PASS | `audio-routes-reconcile: ok` |
| FFADO enumeration | `timeout 5 ffado-test ListDevices` | PASS | Enumerated `Focusrite - SAFFIRE_PRO_24`, GUID `0x00130e0401c04de0` |
| PipeWire port list | `timeout 5 pw-link -io` | PASS | Saffire and Ardour ports visible |
| PipeWire link list | `timeout 5 pw-link -l` | PASS | Saffire-to-Ardour and Ardour-to-Saffire links present |
| PipeWire link object state | `pw-dump` filtered for links | PASS for routing | Links active, no link errors |
| Direct capture | `timeout 6 pw-record --target saffire_ffado_input --rate 48000 --channels 1 /tmp/saffire-input-test.wav` | FAIL | Only a 44-byte WAV header was written, no audio frames |
| `pw-top` runtime timing | `timeout 5 pw-top -b` | FAIL / suspicious | Saffire and Ardour nodes running but `QUANT 0`, `WAIT 0.0us`, `W/Q ???`, `B/Q ???` |
| `ffado-diag` | `ffado-diag` | FAIL / inconsistent | Exits 1, reports `/dev/fw* []`, but `ffado-test ListDevices` works and PipeWire owns `/dev/fw2` |
| ACL check | `getfacl /dev/fw0 /dev/fw1 /dev/fw2` | INCONCLUSIVE | Twice returned `No such file or directory` even though `ls -l /dev/fw*` immediately before/after showed the nodes |

## Findings

1. The live graph is not missing its expected FFADO nodes or links.

   `saffire_ffado_output`, `saffire_ffado_input`, and `ardour` all exist. The important links are active. The repo tests that assert live aliases and routing all pass.

2. The failure is reproducible outside Ardour.

   `pw-record` from `saffire_ffado_input` created a WAV file but wrote no audio frames. This supports the report that Ardour meters do not move, and points below Ardour.

3. PipeWire's FFADO driver reports a clear failure sequence.

   After startup and device discovery, there are 23 FFADO/PipeWire xruns, then `mod.ffado-driver: FFADO error`. After that, nodes remain visible and marked running but do not appear to process.

4. The FFADO device is accessible and enumerable.

   `ffado-test ListDevices` sees `Focusrite - SAFFIRE_PRO_24` on port 0. PipeWire has multiple open FDs on `/dev/fw2`.

5. ALSA FireWire ownership does not appear to be the issue.

   `snd_dice` and `snd_fireworks` are blacklisted and were not loaded. `aplay -l` does not show the Saffire as an ALSA device.

6. There may be a realtime scheduling mismatch.

   The PipeWire RT thread shown by `ps` is `SCHED_FIFO` priority 1, not the configured `ffado.rtprio = 93`. This may be expected if the FFADO streaming thread is not visible under the simple process name filter, but it is worth asking about. FireWire IRQ threads are priority 51.

7. Kernel FireWire logged `isochronous cycle inconsistent` at boot for the controller hosting the Saffire.

   This appears before PipeWire starts. It may or may not be relevant, but given the FFADO xrun/error pattern and FireWire isochronous transport, it should be included in the upstream report.

## Mailing List Summary Draft

Subject idea: `PipeWire 1.6.5 FFADO Saffire Pro 24: nodes/links present but graph stops after xruns and FFADO error`

Summary:

I switched a Focusrite Saffire Pro 24 from PipeWire ALSA FireWire nodes to PipeWire's FFADO driver on NixOS 26.05. The PipeWire graph comes up and WirePlumber links Ardour to the expected FFADO ports, but Ardour meters do not move. A direct `pw-record` from the FFADO source writes only a 44-byte WAV header over six seconds, so the problem reproduces without relying on Ardour's UI.

Runtime:

- Kernel: Linux 7.0.12, PREEMPT_DYNAMIC
- PipeWire: 1.6.5
- WirePlumber: 0.5.14
- FFADO: 2.4.9
- Device: Focusrite Saffire Pro 24, GUID `0x00130e0401c04de0`
- FireWire controllers: two LSI FW643 controllers
- Saffire attached as `/dev/fw2`, PipeWire owns `/dev/fw2`
- ALSA FireWire modules `snd_dice` and `snd_fireworks` are blacklisted and not loaded

PipeWire FFADO config:

```text
context.modules = [
  {
    name = libpipewire-module-ffado-driver
    args = {
      driver.mode = duplex
      ffado.devices = [ "hw:0" ]
      ffado.period-size = 1024
      ffado.period-num = 3
      ffado.sample-rate = 48000
      ffado.realtime = true
      ffado.rtprio = 93
      sink.props = {
        node.name = "saffire_ffado_output"
        node.description = "Saffire Pro 24 FFADO Output"
      }
      source.props = {
        node.name = "saffire_ffado_input"
        node.description = "Saffire Pro 24 FFADO Input"
      }
    }
    flags = [ ifexists nofail ]
  }
]
```

Key log:

```text
Jun 18 09:57:28 deepthought pipewire[2579]: ffado_streaming_init: libffado 2.4.9 built Jun 26 2024 09:44:00
Jun 18 09:57:28 deepthought pipewire[2579]: Nick name        : Pro24-004de0
Jun 18 09:57:28 deepthought pipewire[2579]: Clock Status     : locked 0x02
Jun 18 09:57:28 deepthought pipewire[2579]: Samplerate       : 0x0000BB80 (48000)
Jun 18 09:57:39 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:1 PipeWire:1 source:1 sink:1
...
Jun 18 10:00:53 deepthought pipewire[2579]: mod.ffado-driver: Xrun FFADO:23 PipeWire:23 source:1 sink:1
Jun 18 10:01:07 deepthought pipewire[2579]: mod.ffado-driver: FFADO error
```

After this error, `wpctl status` and `pw-link` still show the FFADO nodes and links, but `pw-top` shows the Saffire and Ardour nodes with `QUANT 0`, `WAIT 0.0us`, and no useful processing activity. `pw-record --target saffire_ffado_input` writes only a WAV header.

Question for upstream:

What should I collect next to determine whether this is a PipeWire FFADO driver issue, a libffado/DICE issue, a FireWire controller/isochronous scheduling issue, or a realtime scheduling issue? In particular, should `ffado.rtprio = 93` produce a visible RT thread above priority 1, and is `isochronous cycle inconsistent` on `firewire_ohci` significant for this failure mode?

