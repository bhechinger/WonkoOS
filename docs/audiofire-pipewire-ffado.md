# PipeWire/FFADO FireWire audio

- **Status:** The patched NixOS generation 167 and ordered external-host Home
  Manager generation are active. Saffire production duplex passes at
  48 kHz/256/2 with normal Ardour, its complete managed routes, plugins, saved
  session, and eight CPU workers for two minutes with zero steady-state xruns
  or graph errors. AudioFire is exported from a distinct PipeWire PID into the
  same graph, suspended with exactly zero links. Ardour and AudioFire autostart
  are restored and enabled. Stop and bulk route-rebuild transitions can still
  cause a single recoverable FFADO xrun; steady-state operation is clean.
- **Host:** `deepthought`
- **Last updated:** 2026-08-12

This is the source of truth for the experiment. Update the status, checklist,
decision log, and test log as work proceeds. Preserve earlier results; when a
decision changes, append a dated replacement instead of deleting history.

## Current production objective

Run the Saffire Pro24 as the production 48 kHz/256-frame/two-period FFADO
duplex interface. Expose the AudioFire4 in the same PipeWire graph from a
separate FFADO host process, but keep every AudioFire port disconnected until
its routing is designed explicitly.

Success requires the Saffire capture and playback ports to retain the existing
Ardour routes, the PipeWire graph to run at 48 kHz/256 frames, and both
AudioFire FFADO nodes to exist with zero links. The AudioFire must not become a
default device or an automatic Ardour physical-port connection.

## Original isolated experiment objective

Run an on-demand PipeWire instance using FFADO for the Echo AudioFire4 without
restarting, changing, or audibly interrupting the production PipeWire/ALSA
graph used by the Focusrite Saffire Pro24.

Success requires stable AudioFire4 capture and playback while the production
PipeWire PID, socket, defaults, Saffire nodes, and active streams remain
unchanged. Nodes without stable streaming count only as partial success.

## Recorded baseline

Observed before implementation:

- Production PipeWire is 1.6.6 and WirePlumber is 0.5.14.
- Production audio uses the Saffire through ALSA at 48 kHz with a 1024-frame
  quantum.
- AudioFire4 GUID: `0x0014866faf73b593`; observed as `/dev/fw3` on controller
  `07:00.0` when both interfaces were powered.
- Saffire Pro24 GUID: `0x00130e0401c04de0`; observed as `/dev/fw2` on controller
  `06:00.0`.
- FFADO enumeration observed the AudioFire on port 0/node 0 and the Saffire on
  port 1/node 1. Those numbers are dynamic and are not used by this setup.
- `snd_fireworks` is blacklisted for the AudioFire, while `snd_dice` owns the
  Saffire. `musnix.ffado.enable`, audio-group access, and realtime limits are
  already configured.
- The repository had unrelated uncommitted changes before this work, including
  edits in `home/audio.nix` and `home/wireplumber/saffire-clock.conf`; they must
  be preserved.

An earlier isolated prototype copied a complete PipeWire configuration and
selected `hw:0`. A later Saffire FFADO test produced nodes and links but then
xruns, a FFADO streaming error, a `QUANT 0` condition, and an unusable 44-byte
recording. This version instead uses PipeWire's stock configuration plus one
drop-in and binds the AudioFire by GUID.

## Decisions

- **2026-08-11:** Supersede the isolated-instance deployment with one production
  PipeWire graph containing both GUID-selected FFADO devices. Remove the manual
  isolated services so they cannot contend for the AudioFire.
- **2026-08-11:** Run both interfaces at 48 kHz/256 frames/two periods using the
  tested PipeWire 1.6.8, FFADO 2.5.0, and local FFADO-driver fixes.
- **2026-08-11:** Give the Saffire and AudioFire separate PipeWire node groups.
  PipeWire otherwise assigns every FFADO module to the same `ffado-group`.
- **2026-08-11:** Make the Saffire the high-priority production driver. Give the
  AudioFire the lowest session/driver priority, disable its autoconnection, and
  have the routing policy remove any AudioFire link. This also counters Ardour's
  automatic links to newly appearing physical ports.
- **2026-08-11:** Blacklist `snd_dice` as well as `snd_fireworks`; FFADO needs
  exclusive userspace access to the Saffire and AudioFire respectively.
- **2026-08-11:** Put `firewire_ohci` first in rtirq at priority 95. Live
  validation gives the two controller IRQs FIFO 95 and 94, above the Saffire
  FFADO receive/transmit threads at FIFO 92/94 and PipeWire's data loop at FIFO
  88.
- **2026-08-11:** Keep the Saffire on controller `07:00.0` and the AudioFire on
  `06:00.0`. Saffire 256/2 repeatedly failed on `06:00.0`, but passed the full
  load test after a physical power cycle and controller swap.
- **2026-08-11:** Fix PipeWire's FFADO stop/close recursion. Upstream
  `close_ffado_device()` calls `stop_ffado_device()`, which called
  `close_ffado_device()` again and consequently finished the same FFADO handle
  twice. Stopping now stops streaming; the outer close owns the single finish.
- **2026-08-11:** Mark AudioFire ports non-physical in the local FFADO module
  patch. Together with disabled autoconnection and the WirePlumber link guard,
  this keeps Ardour and policy clients from plumbing the idle interface.
- **2026-08-11:** Regenerate and apply-check the local PipeWire patch against
  pristine 1.6.8 source. The built source contains all four intended fixes:
  callback-position lifetime, single-direction readiness, configurable
  `port.physical`, and single-owner FFADO close.

- **2026-08-11:** Keep production PipeWire, WirePlumber, ALSA monitoring, and
  the Saffire configuration untouched.
- **2026-08-11:** Use the flake's existing unstable package set: PipeWire 1.6.8
  and WirePlumber 0.5.15. PipeWire uses FFADO 2.4.9.
- **2026-08-11:** Select `guid:0x0014866faf73b593`, never a FireWire port number
  or `hw:0`.
- **2026-08-11:** Start conservatively at 48 kHz, 1024 frames, and three
  periods. Tune only after stable streaming is demonstrated.
- **2026-08-11:** Provide no PulseAudio server, JACK bridge, automatic links,
  or automatic startup for the isolated graph.
- **2026-08-11:** Run WirePlumber's policy-only profile with isolated transient
  state so it cannot enumerate ALSA devices or reuse production policy state.
- **2026-08-11:** Use one `audiofire-pw` environment wrapper rather than
  separate wrappers for every PipeWire client tool.
- **2026-08-11:** Keep FFADO verbosity at level 6 while diagnosing startup;
  reduce it after stable streaming is established.
- **2026-08-11:** Set the FFADO module's `remote.name` to PipeWire's special
  `internal` remote. The module loads while the daemon context is being built,
  before the isolated native socket can accept its default client connection.
- **2026-08-11:** Disable WirePlumber's suspend timeout on both FFADO nodes.
  FFADO 2.4.9 crashed when PipeWire suspended and closed the device immediately
  after a capture client disconnected.
- **2026-08-11:** Replace only the isolated PipeWire package's FFADO dependency
  with the official FFADO 2.5.0 release. Keep production and every PipeWire
  parameter unchanged for a controlled comparison.
- **2026-08-11:** Drop the attempted PipeWire workaround which called
  `ffado_streaming_stop()` after a partial start. FFADO crashed inside that
  call before it returned, so the workaround did not make teardown safe.
- **2026-08-11:** Carry a local isolated-PipeWire patch which allows a
  single-direction FFADO graph to run without requiring the absent opposite
  direction to be ready. Upstream PipeWire master still contains the faulty
  readiness checks.
- **2026-08-11:** Keep the installed experiment in playback-only (`sink`) mode.
  Capture-only (`source`) was also validated; duplex remains unsafe.
- **2026-08-11:** Let isolated WirePlumber retry after one second when its first
  connection races with FFADO's blocking startup probe.
- **2026-08-11:** A raw1394 bus reset is an acceptable recovery only on port 0,
  after verifying that port 0 is the dedicated `07:00.0` AudioFire controller.
  Never reset port 1, which owns the production Saffire.
- **2026-08-11:** Supersede the earlier playback-only default and leave the
  installed experiment in capture-only (`source`) mode while duplex is broken.
  Physical input and output have now both been validated independently.
- **2026-08-11:** Do not infer hardware channels from automatic mono linking.
  WirePlumber remixed the first mono test. Direct links establish AudioFire
  FFADO AUX0 as headphone left and AUX1 as headphone right.
- **2026-08-11:** Supersede the conclusion that duplex cannot start. After an
  AudioFire-only bus reset, the same FFADO 2.5.0 configuration started duplex
  reliably and exposed all seven capture and seven playback ports.
- **2026-08-11:** Carry a second local isolated-PipeWire fix for shutdown. The
  FFADO capture callback must inspect its valid `position` argument rather than
  `impl->position`, which PipeWire clears while removing the node. This removes
  a reproducible null dereference during context destruction. An attempted
  teardown reorder did not affect the crash and was removed.
- **2026-08-11:** Supersede capture-only as the installed mode. Leave the
  experiment in `duplex`, manual, and stopped by default. Reduce FFADO logging
  from diagnostic level 6 to level 3 after successful validation.
- **2026-08-11:** Use one persistent playback client for repeated physical
  announcements. Rapidly creating short-lived direct-link clients can leave
  clients waiting and drive FFADO into recoverable xrun handling; this is a
  resilience limitation, not an isolation failure.
- **2026-08-11:** Supersede the conservative 1024/3 setting with 256/2. It is
  the lowest tested setting with zero FFADO xruns and zero PipeWire graph
  errors under six-channel duplex plus eight low-priority CPU workers. At 48
  kHz its nominal FFADO buffering is 10.67 ms, down from 64 ms at 1024/3.
- **2026-08-11:** Reject 128/2 as unsafe: it produced four FFADO xruns during a
  30-second unloaded run, a fifth after client disconnect, and a libffado
  `waitForPeriod`/`ffado_streaming_finish` shutdown crash. Do not probe 64/2.
- **2026-08-11:** Keep 128/3 as an observed normal-load option, not the default.
  It ran for 30 seconds with zero xruns and shut down cleanly, but under the
  bounded CPU load its PipeWire clients missed graph cycles even while FFADO
  remained at zero xruns.
- **2026-08-11:** Do not add scheduling changes from the Interfacing Linux
  guide. Live inspection already showed the PipeWire process at nice -11, its
  data loop at FIFO 88, FFADO transmit at FIFO 89, and receive at FIFO 87;
  memlock is unlimited and `snd_fireworks` is already blacklisted.
- **2026-08-11:** Supersede the one-process/two-module design. Loading both
  FFADO modules in the main PipeWire process causes immediate Saffire xruns,
  even while the AudioFire nodes are suspended and unlinked. Keep only the
  Saffire module in the core and export AudioFire nodes through a persistent
  `pw-cli` client process connected to `pipewire-0`.
- **2026-08-11:** Feed `pw-cli` the readable AudioFire `load-module` file as
  one flattened command. `pw-cli` parses input by line; the original multiline
  pipe loaded only `{`, selected default `hw:0`, and contended for both devices.
- **2026-08-11:** Supersede the `pw-cli` exporter decision. `pw-cli
  load-module` asks the remote daemon to instantiate the module, so AudioFire
  FFADO still ran inside the production PipeWire PID. Run a second PipeWire
  daemon as the module host instead; its FFADO module uses
  `remote.name=pipewire-0` to publish nodes directly into the production graph.
- **2026-08-11:** Serialize FireWire discovery. The external AudioFire host
  waits until both production Saffire nodes report `running`, then allows five
  settling seconds before loading FFADO. Merely waiting for the PipeWire socket
  let both FFADO discovery passes overlap and destabilized Saffire startup.
- **2026-08-11:** Pin Ardour's PipeWire client latency to `256/48000`, clear its
  stale JACK/PipeWire device selection (`DualSense Wireless Controller`), and
  change its stored buffer size from 1024 to 256. The FFADO graph is fixed at
  256 frames; Ardour must not retain the previous 1024-frame engine state.
- **2026-08-11:** Treat Saffire-only direct-client load and full-Ardour load as
  separate tests. The former passes for two minutes under eight-worker CPU
  pressure; the latter fails quickly, so the next controlled comparison runs
  the existing Ardour session against a Saffire-only isolated core.
- **2026-08-11:** Persist the verified system as NixOS generation 166 before
  the recovery reboot. Generation 165 still contained PipeWire 1.6.6 even
  though the 1.6.8 system had been activated transiently. Loader default 166
  now boots store path `501y10w2nad7k86ws77shcnxrx8q38ad` directly.
- **2026-08-12:** Disable Ardour's
  `work-around-jack-no-copy-optimization`. Ardour 9.7 enables it by default and
  connects every physical input to hidden monitor-enable ports. PipeWire JACK
  does not need this JACK no-copy workaround, and those links alone reproduce
  the FFADO failure. Home Manager changes only this mutable Ardour preference.
- **2026-08-12:** Fix FFADO duplex period completion at the driver boundary.
  `on_ffado_timeout()` sets `done=false` and triggers capture. Capture transfers
  data and clears `triggered`; playback transfers data but the upstream driver
  excluded duplex from setting `done=true`. It therefore depended on an
  accidental second capture callback. A normal capture-to-Ardour-to-playback
  chain invokes each callback once and was falsely reported late every period.
  Playback now completes the period when capture has already transferred.
- **2026-08-12:** Restore FFADO's required source-driver ordering. In duplex,
  `on_ffado_timeout()` always calls `pw_filter_trigger_process()` on source;
  upstream therefore assigns source priority 35001 and sink 35000. The local
  configuration had reversed that relationship, selecting sink as the graph
  driver and preventing traversal into its playback callback. Saffire now uses
  source 4001/sink 4000; AudioFire uses source 11/sink 10.

## Production operation

The FireWire graph uses the normal user PipeWire services:

```console
systemctl --user status pipewire.service audiofire-ffado-export.service wireplumber.service ardour-default.service
pw-link -io
pw-dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node") | .info.props["node.name"]'
```

Expected FFADO nodes are `saffire_ffado_input`, `saffire_ffado_output`,
`audiofire_ffado_input`, and `audiofire_ffado_output`. The first two are hosted
by the production PipeWire process; the latter two are hosted by the separate
PipeWire PID owned by `audiofire-ffado-export.service` and exported to the same
core. The AudioFire nodes must have zero links until routing is explicitly
designed. The retired manual isolated target and wrapper are no longer
installed.

## Implementation checklist

### Production migration

- [x] Define one patched PipeWire/FFADO package shared by NixOS and Home Manager.
- [x] Add GUID-bound Saffire and AudioFire duplex modules at 48 kHz/256/2,
  then separate their process ownership after the combined process failed.
- [x] Give the modules separate groups and priorities.
- [x] Convert Saffire readiness and Ardour routes from ALSA names to FFADO ports.
- [x] Add a policy guard which removes every AudioFire link.
- [x] Blacklist `snd_dice` and remove the obsolete isolated service definitions.
- [x] Build the NixOS and Home Manager generations.
- [x] Activate the final NixOS and Home Manager generations.
- [x] Release the loaded `snd_dice` module.
- [x] Start production PipeWire with the Saffire module and the separate
  AudioFire export host after the final patch.
- [x] Verify Saffire duplex nodes, 256/2 timing, and existing Ardour routes.
- [x] Verify both AudioFire nodes are present and have zero links.
- [x] Reboot into generation 166 and restore both FireWire GUIDs.
- [x] Identify that the `pw-cli` exporter loaded AudioFire FFADO inside the
  production daemon rather than the client process.
- [x] Replace it with an external PipeWire module host and serialize AudioFire
  startup after Saffire reaches `running`.
- [x] Correct Ardour's saved JACK/PipeWire device and buffer state and pin its
  client latency to 256/48000.
- [ ] Reboot once to clear the failed FFADO transport.
- [ ] Complete a clean restart and two-minute, eight-worker production load
  test with Ardour and the unlinked AudioFire export active.

### Isolated experiment

- [x] Add the GUID-bound FFADO PipeWire drop-in.
- [x] Add manual PipeWire and policy-only WirePlumber user services.
- [x] Add the manual `audiofire-ffado.target` and `audiofire-pw` wrapper.
- [x] Keep the experiment's configuration, runtime directory, socket, and
  WirePlumber state separate from production.
- [x] Build the Home Manager activation package.
- [x] Activate the Home Manager generation without reloading Hyprland.
- [x] Snapshot and compare the production graph before, during, and after the
  experiment.
- [x] Confirm only AudioFire FFADO nodes appear in the isolated graph.
- [x] Attempt five-second capture and playback. Capture completed with silence;
  playback stalled and accumulated xruns.
- [x] Stop the target and confirm its processes and runtime directory disappear
  while production audio continues. PipeWire crashed during FFADO teardown, so
  shutdown is not clean.
- [x] Compare FFADO 2.5.0 with 2.4.9. Duplex startup and its partial-start
  teardown crash are unchanged.
- [x] Validate capture-only transport after an AudioFire-only bus reset: five
  seconds at 48 kHz, zero xruns, client disconnect survived, clean shutdown.
- [x] Validate playback-only transport using a silent five-second WAV: zero
  xruns, client disconnect survived, clean shutdown.
- [x] Demonstrate meaningful nonzero capture with a known signal connected to
  an AudioFire input.
- [x] Demonstrate physical headphone playback and map AUX0 to left and AUX1 to
  right using direct, non-remixed links.
- [x] Achieve simultaneous physical capture and playback with direct links and
  zero xruns.
- [x] Repeat three fresh duplex start/run/stop cycles with zero transport xruns,
  normal service exit, no coredump, and complete runtime-directory cleanup.
- [x] Tune and load-test 1024/3, 512/2, 256/2, 128/3, and 128/2 with the same
  six-channel full-duplex workload; leave the lowest fully clean setting
  installed.

## Test log

### 2026-08-11 — Configuration implementation

- Home Manager path-flake build: passed.
- Home Manager activation: passed; the manual target remained stopped.
- Production before activation: PipeWire PID 2259, cookie 2320201852,
  WirePlumber PID 2262, 48 kHz/1024 frames, with an active Firefox stream.
- First isolated start: failed. PipeWire 1.6.8 reported
  `mod.ffado-driver: can't connect: Host is down` while loading the mandatory
  FFADO module. The isolated processes exited and production retained the same
  PID and cookie.
- Source and merged-config inspection showed that this failure happened before
  `ffado_streaming_init`: the module tried to connect as a client before the
  isolated core socket existed. The module is now directed to the local
  `internal` context for the next test.
- `ffado-test ListDevices` still found the AudioFire at port 0/node 0 and the
  Saffire at port 1/node 1 after the failure.
- The generic `ffado-test-streaming` program supplies no device selector and
  passes an empty device list to FFADO, so it was not run while the production
  Saffire was active.
- With the internal-core fix, the isolated graph started as PipeWire 1.6.8 PID
  160926/cookie 897252309 with WirePlumber 0.5.15 and fourteen AudioFire ports.
  Production remained PID 2259/cookie 2320201852.
- The first linked capture wrote a 960,044-byte, five-second, stereo 48 kHz
  PCM file, then the isolated daemon crashed in a race between
  `ffado_streaming_wait` and `ffado_streaming_finish` while suspending the
  device. Playback was deliberately skipped.
- A PipeWire-only retry stayed alive but produced only a 44-byte WAV because no
  policy manager created the target links. Live inspection with WirePlumber
  showed the FFADO node suspended despite `node.pause-on-idle=false`; the next
  test disables WirePlumber's suspend timeout explicitly.
- With suspend disabled, capture wrote exactly 480,000 stereo samples in a
  960,044-byte WAV. Every sample was zero. `pw-top` reported 48 kHz, quantum
  1024, and zero PipeWire graph errors, and the daemon survived capture-client
  disconnect.
- Playback of that silent file did not complete. FFADO accumulated 24 xruns and
  repeatedly failed to align or receive periods while the PipeWire graph still
  reported zero errors.
- Stopping the target removed both isolated processes and
  `/run/user/1000/pipewire-audiofire`, but PipeWire exited with `SIGSEGV`. The
  coredump again shows `ffado_streaming_wait` racing with
  `ffado_streaming_finish`.
- Final production check: PipeWire PID 2259/cookie 2320201852 and WirePlumber
  PID 2262 remained unchanged; the Firefox stream was active after shutdown.

### 2026-08-11 — FFADO 2.5.0 and single-direction recovery

- Built the isolated PipeWire 1.6.8 module against official FFADO 2.5.0. `ldd`
  confirmed that only the isolated FFADO module uses the new library.
- A controlled duplex capture reproduced the failure: FFADO timed out putting
  its receive processor into dry-running state, retried an already enabled
  receive handler, failed `syncStartAll`, and crashed during handler teardown.
  The output was a 44-byte WAV. Production remained PID 2259/cookie
  2320201852.
- FFADO 2.5.0 release notes contain no streaming fix, and its streaming source
  files are identical to 2.4.9. PipeWire upstream master also retains the same
  module startup, reset, and single-direction readiness logic.
- A first local patch tried to stop FFADO after a partial startup. The stop call
  itself reached `~IsoHandler: BUG: Handler still running!` and segfaulted, so
  the patch was removed.
- The retained local patch corrects PipeWire's single-direction readiness
  checks. Without it, source-only discards capture buffers and sink-only sends
  silence because each incorrectly waits for the absent opposite filter.
- Repeated failed starts left raw1394 port 0 unable to dry-run the receive
  processor. `/dev/fw3` and `/dev/fw1` map to PCI controller `07:00.0`, while
  the Saffire `/dev/fw2` maps to `06:00.0`. Source inspection confirmed that
  `ffado-test -p 0 BusReset` resets only the selected raw1394 port. The port-0
  reset recovered the AudioFire; the production PID, cookie, Saffire nodes,
  and Firefox/Spotify streams remained present.
- Capture-only then ran for five seconds and remained active for more than a
  minute with zero xruns. It wrote a 960,044-byte, stereo 48 kHz WAV containing
  480,000 samples. Only one sample had value 1 and all others were zero, so
  transport is stable but useful input data is not yet demonstrated. Client
  disconnect and target shutdown were clean.
- Playback-only completed the same five-second silent WAV with zero xruns.
  Client disconnect and target shutdown were clean. This is the currently
  installed mode at this stage of the test log; the later duplex decision
  supersedes it.
- On one cold start WirePlumber connected before PipeWire completed FFADO's
  blocking probe and exited with status 69. The configured one-second restart
  connected successfully (`NRestarts=1`) without operator action.

### 2026-08-11 — Physical input and output validation

- Playback used the installed ALSA `Front_Left.wav` and `Front_Right.wav`
  identification samples at 3% PipeWire stream volume. The user confirmed
  headphone output.
- Automatic mono targeting played on both channels, and an automatic AUX1 test
  still selected the left output. With automatic remixing bypassed and links
  made directly, FFADO AUX0 (`Unknown_in`) played only on the left and AUX1
  (`Unknown0_in`) played only on the right.
- Five successive automatically linked playback clients triggered one
  recoverable FFADO xrun and left the service failed during shutdown. An
  AudioFire-only raw1394 port-0 reset recovered it. Subsequent direct AUX0 and
  AUX1 tests ran with zero xruns.
- Capture used a microphone on physical input 1 with the trim at 50%. FFADO
  AUX0 (`Unknown_out`) was linked directly to a mono recorder for ten seconds.
  The resulting 960,044-byte, 48 kHz/16-bit WAV contains 480,000 samples:
  479,512 nonzero, minimum -6159, maximum 5364, RMS 1105.57, and no clipped
  samples. FFADO reported zero xruns.
- Capture client disconnect and target shutdown were clean; the isolated
  runtime directory was removed. Production remained PipeWire PID 2259/cookie
  2320201852 throughout all physical tests.

### 2026-08-11 — Duplex recovery and shutdown fix

- After changing the installed mode to `duplex` and resetting only raw1394 port
  0, the AudioFire started cleanly with seven capture and seven playback ports.
  The earlier synchronization failure was persistent controller/device state,
  not a permanent inability to run duplex.
- A direct simultaneous voice-capture and playback run remained active for
  about five minutes. The microphone recording contained 480,000 samples,
  478,647 nonzero, minimum -8318, maximum 7148, RMS 1190.15, and no clipping.
  One client transition caused a recoverable FFADO xrun; the daemon remained
  active.
- Stopping the target then reproducibly crashed PipeWire. Coredumps 381071 and
  480496 put the data thread at `source_process` while the main thread removed
  the filter node. Disassembly mapped the exact fault at module offset `0xe6f8`
  to dereferencing `impl->position`; `stream_io_changed` sets that pointer to
  null during node removal. Reordering module teardown did not help and was
  removed.
- The retained one-line fix reads xrun-recovery flags from the callback's valid
  `position` argument. The Home Manager path-flake build and activation passed.
- Three fresh duplex cycles then completed direct mono capture plus stereo
  silent playback. Each had successful direct links, 240,000 captured mono
  samples, and zero FFADO xruns. Every target stop exited with status 0, made no
  coredump, and removed `/run/user/1000/pipewire-audiofire`. Cycles two and
  three started without another bus reset, proving clean teardown leaves the
  hardware reusable.
- Two aborted physical-test shells temporarily left multiple short playback
  clients alive. That contaminated graph accumulated 50 recoverable FFADO
  xruns. Killing only those test clients and stopping the target still produced
  a clean exit with no coredump. A port-0-only reset restored the AudioFire for
  the final controlled run.
- The final physical duplex run used one persistent playback client containing
  five `Front_Left.wav` payloads while directly recording microphone input 1
  for 15 seconds. Both links succeeded and FFADO reported zero xruns. The user
  confirmed all five announcements in the left headphone. The WAV contains
  720,000 samples, 718,946 nonzero, minimum -2414, maximum 2605, RMS 460.93,
  and no clipping.
- Final shutdown was clean with no coredump or runtime directory. Production
  remained PipeWire 1.6.6 PID 2259/cookie 2320201852 with the Saffire and its
  application streams present.

### 2026-08-11 — Buffer tuning and load test

- The repeatable workload linked all six AudioFire audio channels in both
  directions: float32 zero playback plus capture to `/dev/null`. The seventh
  FFADO port in each direction is MIDI and was deliberately excluded. Eleven
  links were created passive and the twelfth active so graph startup could not
  contaminate the candidate with incremental-link errors.
- 1024/3 control: 30 seconds, zero PipeWire errors, zero FFADO xruns across 15
  reports.
- 512/2: 30 seconds, zero PipeWire errors, zero FFADO xruns across 29 reports.
- 256/2: 30 seconds unloaded, zero PipeWire errors, zero FFADO xruns across 57
  reports. A second two-minute run saturated eight of the workstation's 16
  CPUs with nice-15 workers; all six channels still ran both ways with zero
  PipeWire errors and zero FFADO xruns across 244 reports. Post-client and
  pre-shutdown observation reached 288 reports with the count still zero.
- 128/2: the 30-second unloaded run showed zero sampled PipeWire errors but
  accumulated four FFADO xruns across 113 reports, then a fifth after client
  disconnect. Shutdown coredump 629927 was a libffado race between
  `StreamProcessor::getTimeAtPeriod`/`waitForPeriod` and
  `ffado_streaming_finish`; this is distinct from the fixed PipeWire
  `impl->position` null dereference. A port-0-only reset recovered the device.
- The Interfacing Linux guide's 128/3 example was tested. It completed 30
  unloaded seconds with zero PipeWire errors and zero FFADO xruns across 113
  reports, remained at zero across 251 reports after client disconnect, and
  shut down cleanly. Under eight-worker CPU pressure, FFADO stayed at zero but
  the playback and capture clients accumulated graph errors, so it was not
  selected for the load-tested default.
- Live scheduling inspection during 128/3 showed that existing configuration
  already meets the guide's useful realtime intent: PipeWire nice -11, data
  loop FIFO 88, FFADO transmit FIFO 89, and receive FIFO 87. Raising priority
  was therefore not tested as a substitute for buffer headroom.
- Production remained PipeWire 1.6.6 PID 2259/cookie 2320201852 with the
  Saffire present. Every passing candidate stopped normally with no coredump or
  runtime directory.

### 2026-08-11 — Production Saffire migration

- The first production PipeWire 1.6.8 graph exposed both duplex devices at
  256/2. Existing Saffire-to-Ardour routes were correct, both AudioFire nodes
  remained idle, and no link touched an AudioFire node.
- Saffire streaming on controller `06:00.0` accumulated xruns and eventually
  failed with an unhandled FFADO error. Giving the FireWire IRQs FIFO 95/94
  removed the observed priority inversion but did not make that controller
  stable at 256/2. Saffire-only 256/2 failed too, ruling out AudioFire
  coexistence as the cause. A 256/3 probe failed during initialization and was
  not a valid latency result.
- PCI hot-remove/rescan cleared Linux's wedged controller handle but left the
  controller runtime-power state `on`; it did not power-cycle the bus-powered
  Saffire. The Saffire and AudioFire cables were physically swapped, moving the
  Saffire to `07:00.0` and AudioFire to `06:00.0` while power-cycling both.
- On `07:00.0`, Saffire-only 256/2 initialized immediately. Both FFADO nodes
  and Ardour remained running for two minutes while eight `sha256sum` workers
  saturated CPUs. The complete interval had zero journal lines matching xrun,
  error, fatal, or `QUANT`; all workers exited normally.
- Shutdown exposed an independent upstream recursion: the FFADO module stopped
  and closed the same device from both `stop_ffado_device()` and its caller,
  then called `ffado_streaming_finish()` twice. The local patch now removes the
  recursive close. The resulting NixOS and Home Manager path-flake builds pass.
- The source-verified final build exposed the correct two-device production
  graph. Saffire routes were present; every AudioFire port reported
  `port.physical=false`; both AudioFire nodes stayed suspended with exactly zero
  links. Starting Ardour nevertheless produced immediate Saffire xruns while
  the AudioFire never started, so software coexistence was ruled out.
- After stopping that run, PipeWire became stuck in FFADO shutdown and systemd
  retained its killed process as a zombie. An isolated retry then blocked in
  the first Saffire `ffado_streaming_init` call before reaching the AudioFire.
  A full Saffire bus-power cycle and a verified raw1394 port-0 reset did not
  recover it. Standalone FFADO 2.4.9 `Discover` also found the Saffire DICE
  driver and then hung, independently confirming controller/device transport
  state rather than a PipeWire graph or routing failure.
- Resetting `07:00.0` with PCI remove/rescan and its native `pm bus` reset,
  restarting rtirq, resetting the controller-local raw1394 port, and fully
  power-cycling the bus-powered Saffire did not restore its FireWire node.
  Linux sees the local `07:00.0` OHCI node but no remote Saffire GUID on either
  socket. Do not repeat the cable exchange: the same cable worked with the
  previous ALSA configuration and has already been exchanged during this
  investigation. A host reboot is the next recovery boundary.

### 2026-08-11 — Reboot recovery and split FFADO hosts

- The host initially rebooted into an older generation containing PipeWire
  1.6.6, FFADO 2.4.9, and loaded `snd_dice`. Activating
  `/tmp/deepthought-ffado-system-verified` restored the intended PipeWire 1.6.8
  system, removed `snd_dice`, restarted rtirq, and made that generation the
  active and boot default.
- The old ALSA driver left the Saffire DICE owner at `0xFFC00001`. A raw1394
  reset on its then-current FFADO port 1 cleared the owner and allowed FFADO to
  initialize. Port numbers remain dynamic; the GUID mapping was rechecked
  before the reset.
- Saffire-only direct simultaneous playback and capture passed for 20 seconds
  unloaded and 120 seconds with eight `sha256sum /dev/zero` workers. Both runs
  had zero PipeWire graph errors and zero FFADO xruns at 48 kHz/256/2, and the
  controlled process exited cleanly.
- A separate interactive `pw-cli` host then exported both AudioFire nodes into
  the Saffire graph. The AudioFire stayed suspended with exactly zero links.
  Saffire duplex again passed 120 seconds under eight-worker CPU load with zero
  warnings or xruns in either process; unloading the AudioFire module and
  stopping the core were clean.
- The installed `audiofire-ffado-export.service` first exposed a line-oriented
  parsing bug: its multiline command loaded a default `hw:0` FFADO module and
  opened both interfaces. Flattening the command with `tr '\n' ' '` fixed it.
  The corrected service exports the exact named AudioFire nodes from its own
  process; they remain suspended and unlinked.
- The corrected split production graph still develops Saffire xruns as soon as
  the existing Ardour session starts. Ardour connects all Saffire capture
  ports, two playback ports, and additional motherboard/webcam ALSA inputs.
  Because the isolated direct-client tests pass, the remaining suspect is the
  Ardour session workload or another component of the wider managed graph.
- The first isolated-Ardour setup attempt opened the Saffire but published no
  nodes, matching stale DICE ownership. It was force-stopped and `lsof`
  confirmed that neither `/dev/fw2` nor `/dev/fw3` remains open. Reset the
  Saffire bus owner before retrying the controlled Ardour comparison.
- Repeated starts with the exact previously passing `/tmp/saffire-only`
  configuration still blocked inside `ffado_streaming_init`. A verbose
  standalone FFADO 2.4.9 discovery identified the lower-level failure: the
  Saffire GUID and model were read, but the first DICE access to
  `0xFFFFE0000000` failed. FFADO 2.4.9 then crashed in EAP cleanup; that crash
  is a consequence of failed discovery, not the PipeWire patch.
- After a ten-second physical Saffire power cycle, Linux saw a PHY topology
  change on `07:00.0` but could no longer read the remote configuration ROM or
  create its `/dev/fw*` node. A subsequent raw1394 port-1 reset and the
  controller's native `bus` PCI reset did not restore it. The lit Saffire is
  electrically present, but only the AudioFire GUID currently enumerates.

### 2026-08-11 — External-host correction and ordered startup

- Generation 166 booted the exact verified system path
  `501y10w2nad7k86ws77shcnxrx8q38ad`. Both GUIDs returned, with the Saffire on
  raw1394 port 0 and AudioFire on port 1; ALSA FireWire drivers remained
  unloaded.
- Boot logs disproved the installed split-host assumption. The persistent
  `pw-cli` process was only a control client: its `load-module` request caused a
  second FFADO module to execute in the production PipeWire PID. The first
  Saffire xrun followed when the full graph became active.
- The exporter now execs a second PipeWire 1.6.8 daemon with core name
  `audiofire-ffado-host`. Its FFADO module runs in that process while
  `remote.name=pipewire-0` publishes the AudioFire nodes into production. A
  live start confirmed distinct production and AudioFire PipeWire PIDs and
  attributed AudioFire's `ffado_streaming_init` to the external service.
- The first external-host start still raced: AudioFire discovery began one
  second after production PipeWire started, before Saffire's initial probe and
  streaming open had completed. Saffire then accumulated xruns and reached an
  unhandled FFADO error. This is not evidence against process isolation; it is
  a startup-order failure.
- The service now waits for both `saffire_ffado_output` and
  `saffire_ffado_input` to report `running`, then waits five more seconds before
  starting AudioFire FFADO. The Home Manager build, formatting check, and
  whitespace check pass, and that generation is activated without reloading
  the wedged user manager.
- Normal PipeWire shutdown timed out after the FFADO fatal path. Systemd sent
  `SIGKILL` and later reported two tasks still present; both FireWire GUIDs
  nevertheless pass `ffado-test ListDevices`. Reboot is required to clear only
  the stuck process state before validating the ordered design.
- After that reboot, process ownership and ordering were correct: production
  PipeWire was PID 2240, the external AudioFire host was PID 2241, Ardour and
  Saffire were running before AudioFire initialized, and both GUIDs enumerated.
  Saffire's first xrun occurred at 22:32:57; AudioFire did not initialize until
  22:33:01. AudioFire is therefore not the trigger for this production failure.
- Static and live properties show Saffire output as the highest-priority graph
  driver (`priority.driver=4000`) at 48 kHz/256 frames. The null sinks have no
  driver priority, and other ALSA nodes are 696 or lower, ruling out the earlier
  wrong-driver hypothesis.
- Ardour's active JACK/PipeWire engine state still selected the DualSense
  controller and stored `buffer-size=1024`. It is now backed up, cleared to no
  selected device, and changed to 256. The systemd service also exports
  `PIPEWIRE_LATENCY=256/48000`. The Home Manager build and activation pass.
- Stopping the already-fatal FFADO transport again hung in PipeWire shutdown.
  Do not run more forced retries; reboot once and test the corrected Ardour
  engine state from a clean device handle.
- That corrected normal Ardour start still failed before AudioFire existed:
  Saffire's first xrun was at 23:32:22 and AudioFire initialized at 23:32:25.
  Quantum/device state is therefore not the root cause. Ardour and AudioFire
  autostart are temporarily disabled for the next reboot; run the existing
  session once with Ardour's native `-B -P` plugin/port bypass to discriminate
  session workload from base JACK/PipeWire behavior.
- The `-B -P` run still failed. Saffire streaming opened at 23:53:42, the first
  xrun followed at 23:53:45, and FFADO reached the fatal unhandled-xrun path at
  23:54:29. The AudioFire host remained stopped. Ardour was the active JACK
  node at `256/48000`; Saffire output was the graph driver; realtime priorities
  were correct. Plugins, saved Ardour port connections, AudioFire coexistence,
  an incorrect graph driver, and an incorrect quantum are therefore ruled out.
- `-P` does not prevent `audio-routes.lua` from creating its desired links.
  The next clean discriminator is to stop WirePlumber before launching Ardour,
  then add only playback plus a separate capture client to start Saffire
  duplex. If that is stable, add one Saffire-capture-to-Ardour link. This
  separates automatic routing complexity from the feedback-shaped duplex path
  through a single JACK client.
- The policy-free discriminator started from exact generation 166 with both
  GUIDs present, AudioFire stopped, WirePlumber stopped, and Ardour launched
  with `-B -P`. Before any test link was added, Ardour connected all 16 Saffire
  audio capture ports and its MIDI port to hidden
  `physical_*_input_monitor_enable` ports. FFADO initialized at 08:52:07,
  reached its first xrun at 08:52:10, and became fatal at 08:52:38. The Ardour
  9.7 source traces those links directly to its default-enabled JACK no-copy
  workaround, not its monitoring model or session routes.
- The live Ardour config is backed up as
  `config.bak-codex-20260812-before-disable-no-copy`, then changed to set the
  workaround to `0`. Home Manager now enforces the same single option while
  retaining the rest of the mutable config. The replacement/idempotence check,
  Nix formatting, whitespace check, and Home Manager build pass.
- On the next clean boot the hidden ports were absent and both Saffire nodes
  remained suspended while Ardour ran at `256/48000`. Adding only Master L/R
  playback and microphone capture reproduced the same xrun cadence. This rules
  out link count and identifies the single-node duplex topology as the trigger.
- Source inspection explains the topology dependency: the split-client control
  happened to schedule capture twice and passed; the normal three-link chain
  scheduled capture and playback once each, leaving `rt.done` false. Current
  PipeWire upstream still contains that logic. The local patch now recognizes
  capture-plus-playback transfer as completion from either callback, so it is
  independent of callback order and also fixes source-only completion. It
  dry-applies to pristine 1.6.8, and the complete deepthought system build
  succeeds as store path `km5gvjyjml8pmdji5bwblcbdw2f24nn6` with a distinct
  PipeWire binary.
- The first requested `switch-to-configuration boot` did not register the
  earlier build: after reboot, `/run/current-system`, the system profile, and
  systemd-boot all still pointed to generation 166. Do not reboot after the
  replacement activation until the system profile and boot entry are verified.
- The replacement was registered explicitly with `nix-env --profile` before
  running `switch-to-configuration boot`. System generation 167, the system
  profile, `/boot/loader/loader.conf`, and `nixos-generation-167.conf` now all
  point to `km5gvjyjml8pmdji5bwblcbdw2f24nn6`. This is the verified validation
  boot target.
- Generation 167 booted the expected `b30b9446...` PipeWire binary. The first
  three-link run still accumulated xruns because both transfer flags never
  became true: the sink callback was behind the selected sink-driver boundary.
  This supersedes the claim that period completion alone fixed the normal
  topology. The source-driver Home generation builds and activates cleanly;
  activation briefly started managed Ardour, so Ardour and AudioFire were
  stopped and temporarily disabled again before the clean validation reboot.
- On the clean source-driver boot, live graph assignment was correct: Saffire
  input/source node 42 was the driver at priority 4001; Saffire output and
  Ardour followed node 42. The policy-free three-link graph then ran for 35
  seconds with zero xruns or errors, passing the reproducer that had failed on
  every earlier run.
- Starting WirePlumber rebuilt the complete route set. That bulk transition
  briefly suspended both Saffire nodes and caused one recoverable xrun, but the
  graph immediately returned to running. A fresh 30-second managed-route
  window then contained zero xruns or errors.
- The managed graph passed two minutes with eight nice-15
  `sha256sum /dev/zero` workers. Saffire input/output and bypassed Ardour stayed
  running throughout with zero xrun/error/fatal/QUANT journal matches.
- The AudioFire exporter started as independent PipeWire PID 16147. Its output
  and input appeared suspended at priorities 10 and 11 respectively, with
  exactly zero links. A second two-minute eight-worker load test kept Saffire
  running and AudioFire suspended/unlinked with zero errors from either host.
- Stopping the bypassed Ardour client returned Saffire to idle but produced one
  recoverable FFADO drain xrun and CTR discrepancy warnings. This is a bounded
  lifecycle limitation; no process became stuck and the device reopened.
- Normal managed Ardour, including plugins, saved session and full policy
  routes, then ran cleanly. Its final two-minute eight-worker production load
  ended at 10:14:03 with all workers exited, Saffire running under source node
  42, AudioFire suspended with zero links, and zero matching journal errors for
  the entire load interval. Ardour and AudioFire boot enablement is restored.

## Current state and remaining work

Saffire duplex at 48 kHz/256/2 passes direct isolated load testing on its tested
controller, including two minutes with eight CPU workers. The ordered
external-host generation is installed and validated. Saffire production audio
runs at 48 kHz/256/2; normal Ardour and the full managed graph pass the bounded
CPU load; AudioFire is present from its independent host with zero links.

No implementation work remains for the requested steady-state configuration.
Avoid restarting WirePlumber or stopping Ardour during critical audio because
those bulk lifecycle transitions can produce one recoverable FFADO xrun. A
future task may address transition sequencing if seamless graph teardown is
required; it is not needed for stable running audio.

The recovery reboot is safe to perform: `/nix/var/nix/profiles/system` and the
systemd-boot default both point to generation 167, the verified final patched
PipeWire 1.6.8 system. Generation 166 records an earlier validation state;
generation 165 still uses PipeWire 1.6.6.

FireWire port numbers are dynamic and changed during controller resets. Use
GUIDs for configuration and re-check the live device-to-controller mapping
before any recovery action. Do not use generic `ffado-test-streaming` while
either production device is active because it cannot select one interface.

## Historical upstream duplex report draft (superseded)

This draft records the earlier failed-state reproducer. A clean AudioFire bus
later started duplex successfully, and the remaining shutdown crash was fixed
locally as the PipeWire `impl->position` race documented above. Do not submit
this draft as a current duplex-start failure.

**Summary:** PipeWire 1.6.8 with libffado 2.5.0 cannot start an Echo AudioFire4
in duplex mode. FFADO times out starting its receive processor, then segfaults
while destroying the partially started handler.

**Environment:** NixOS on `deepthought`; Echo AudioFire4 GUID
`0x0014866faf73b593`; dedicated LSI FW643 controller; 48 kHz; 1024-frame
period; three periods; realtime priority 88. Production audio is on a separate
controller and is not involved.

**Reproducer:** Load `libpipewire-module-ffado-driver` with:

```text
remote.name = internal
driver.mode = duplex
ffado.devices = [ "guid:0x0014866faf73b593" ]
ffado.period-size = 1024
ffado.period-num = 3
ffado.sample-rate = 48000
ffado.realtime = true
ffado.rtprio = 88
```

Start a capture client against the FFADO source. The first period never
arrives. The characteristic log sequence is:

```text
startDryRunning: Timeout waiting for the SP's to start dry-running
requestEnable: Enable requested on enabled stream 'Receive'
start: Could not syncStartAll...
ffado_streaming_start: Could not start the streaming system
~IsoHandler: BUG: Handler still running!
```

The PipeWire process then receives `SIGSEGV`. Coredump PID 277465 begins:

```text
Streaming::StreamProcessor::packetsStopped
IsoHandlerManager::IsoHandler::disable
IsoHandlerManager::IsoHandler::~IsoHandler
IsoHandlerManager::pruneHandlers
IsoHandlerManager::unregisterStream
ffado_streaming_finish
close_ffado_device
```

Calling `ffado_streaming_stop()` after the partial start also crashes before it
returns. As controls, the same hardware and settings complete physical
capture-only and playback-only tests with zero xruns when each stream is linked
directly. FFADO 2.4.9 behaves the same in duplex mode.

## References

- [PipeWire FFADO driver module](https://docs.pipewire.org/page_module_ffado_driver.html)
- [Interfacing Linux: FireWire + FFADO With PipeWire](https://interfacinglinux.com/2024/07/29/firewire-ffado-with-pipewire/)
- [WirePlumber multiple-instance profiles](https://pipewire.pages.freedesktop.org/wireplumber/daemon/multi_instance.html)
- [FFADO device selector parser](https://sources.debian.org/src/libffado/2.4.9-2/src/DeviceStringParser.cpp/)
- [FFADO 2.5.0 release](https://www.ffado.org/posts/ffado-2.5.0-release/)
- [PipeWire FFADO module source](https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/master/src/modules/module-ffado-driver.c)
