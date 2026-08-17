# PipeWire/FFADO FireWire audio

- **Status:** FFADO work is paused after another instrumented fatal transport
  failure. The configuration, patched source, and two captured failure logs are
  preserved. `useSaffireFfado = false` selects the known PipeWire/ALSA Saffire
  configuration until this investigation resumes.
- **Host:** `deepthought`
- **Last updated:** 2026-08-14

This is the source of truth for the experiment. Update the status, checklist,
decision log, and test log as work proceeds. Preserve earlier results; when a
decision changes, append a dated replacement instead of deleting history.

## Current production objective

Run only the Saffire Pro24 as the production 48 kHz/256-frame/two-period FFADO
duplex interface. Keep the AudioFire physically disconnected and its exporter
disabled.

Success requires the existing Saffire playback/capture routes to return after
reboot, normal physical stereo playback and microphone capture, and no
steady-state xruns beyond the accepted single Ardour-startup event.

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
- **2026-08-13:** Preserve the FFADO device across a PipeWire PAUSED state.
  The first master candidate moved the PAUSED path from
  `stop_ffado_device()` to `close_ffado_device()`. On hardware this recreated
  the DICE streams when Ardour started and wedged the transport. The corrected
  patch keeps stop and close ownership separate while PAUSED performs only a
  stop, exactly matching the stable patched PipeWire 1.6.8 behavior.
- **2026-08-13:** Target the upstream merge request at `master`. PipeWire's
  official GitLab reports `master` as its protected default branch; the other
  active numbered branches are maintenance lines (`1.0`, `1.2`, `1.4`, and
  `1.6`), with no separate development branch. All 54 open merge requests in
  the checked API sample target `master`, as did the two prior FFADO merge
  requests found (#1633 and #1635). Do not target `1.6` directly; upstream can
  decide whether any accepted fix should be backported.
- **2026-08-13:** Push the submission as one signed commit rather than the
  seven incremental hardware-test commits. Branch `fix/ffado-duplex-master` in
  `bhechinger/pipewire` points to `3a2ae07d642e48ad556a38bf246841a00e3fee29`;
  its tree and diff are identical to the tested generation-184 patch.
- **2026-08-14:** Add explanatory mode-comparison comments as a second signed
  commit, `81eeba1f63ed72249e94ee06354acea014546efe`, without changing driver
  behavior. This supersedes only the one-commit branch shape above.
- **2026-08-14:** Use the clean `/home/wonko/src/pipewire` checkout of
  `fix/ffado-duplex-master` as the Nix source through a locked non-flake path
  input. Remove the duplicated local patch files so the merge-request branch
  is the single source of PipeWire driver code.
- **2026-08-14:** Diagnose the fatal transport before adding recovery behavior.
  Keep the merge-request branch unchanged and put temporary tracing on local
  branch `diagnostic/ffado-fatal-trace`. A 4,096-entry allocation-free ring
  records only FFADO wait results, capture/playback transfer results, monotonic
  time, and existing driver state. Dump it once on `ffado_wait_error`; emit no
  steady-state trace logging.
- **2026-08-14:** Pair the module trace with a user watchdog that discovers the
  Saffire controller by GUID and samples its IRQ count plus the PipeWire data
  loop and FFADO ISO thread scheduler counters every 250 ms. Keep samples
  bounded in `$XDG_RUNTIME_DIR` and persist evidence only after the module
  logs `FFADO error`. Do not patch libffado unless this first capture locates
  the fault inside its packet-handler path.
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

### 2026-08-12 — post-deployment xrun and priority correction

- Normal use exposed that the earlier bounded test was not sufficient. At
  256/2, activating Ardour and Firefox repeatedly filled FFADO's playback
  ringbuffer, produced cycle-timer discrepancies and xruns, and eventually
  left playback as a loud right-channel tone with capture stalled. PipeWire
  links were correct; restarting restored clean stereo playback and microphone
  capture, confirming a transport failure rather than a routing error.
- Increasing only `ffado.period-num` to three and four did not prevent the
  same 544-frame playback write from overflowing. Do not retain extra periods
  as a workaround; the final configuration remains 256/2.
- Live scheduling inspection found the Saffire controller IRQ and FFADO
  transmit worker tied at FIFO 94. Lowering `ffado.rtprio` from 93 to 92 put
  the FFADO ARM/transmit/receive workers at FIFO 92/93/91, below IRQ 39 at 94
  and above PipeWire's data loop at 88.
- Before the priority change, 256/4 failed under the eight-worker load. With
  only the live priority changed, the same graph completed two minutes under
  eight nice-15 `sha256sum /dev/zero` workers with zero new PipeWire or FFADO
  xruns, ringbuffer overruns, cycle-timer discrepancies, errors, or timeouts.
- The final 256/2 plus `ffado.rtprio = 92` Home Manager generation built and
  activated successfully. Its restart could not be validated because the old
  xrunned FFADO process hung during teardown and required SIGKILL. The Saffire
  then failed to enumerate after a physical power cycle, controller-local bus
  reset, PCI function reset, PCI hot-remove/rescan, and `firewire_ohci`
  unbind/rebind. PCI still sees `07:00.0`, but no local node or Saffire GUID is
  created; the audio stack is stopped and a host reboot is the next recovery
  boundary.
- Generation 167 rebooted with both FireWire GUIDs present and the final Home
  Manager generation active. Ardour initially waited at its crash-recovery
  prompt; accepting recovery loaded every expected route and caused one
  recoverable FFADO xrun. Firefox then played clean stereo through Ardour and
  the Saffire, and the Saffire microphone reached Ardour correctly.
- The final steady-state test ran the complete normal Ardour graph at
  48 kHz/256/2 for two minutes with eight nice-15 `sha256sum /dev/zero`
  workers. The interval contained zero new FFADO/PipeWire xruns, ringbuffer
  overruns, cycle-timer discrepancies, errors, or timeouts. Both GUIDs remained
  present, all managed Saffire routes remained connected, and AudioFire had
  zero links.
- **2026-08-12:** Accept one recoverable FFADO xrun while Ardour bulk-loads its
  session after startup. Steady-state operation must remain xrun-free; repeated
  xruns, a stuck tone, missing capture, or a failed load interval are not
  acceptable.

### 2026-08-12 — 128/3 production validation

- PipeWire's quantum and Ardour's `PIPEWIRE_LATENCY` were reduced from 256 to
  128 frames, while FFADO changed from two to three periods. Sample rate remains
  48 kHz and `ffado.rtprio` remains 92. The Home Manager check built as
  `/nix/store/p5gpy7nmrv8karikhrg7yxcifxa4i6lk-home-manager-generation` and
  activated successfully.
- Home Manager activation restarted Ardour before PipeWire and caused one
  recoverable transition xrun on the old transport. The deliberate PipeWire
  restart then reproduced the known FFADO shutdown hang; systemd killed only
  the stale process at its stop timeout and started the new one without a
  FireWire controller reset.
- Ardour's initial bulk graph load at 128/3 filled the 511-frame playback
  ringbuffer with a 544-frame write and caused one recoverable startup xrun.
  No further transport errors occurred. Realtime ordering remained IRQ 94,
  FFADO transmit/ARM/receive 93/92/91, and PipeWire data loop 88.
- The user reported normal audio after the restart. The complete managed
  Ardour graph then ran for two minutes with eight nice-15
  `sha256sum /dev/zero` workers and zero new xruns, ringbuffer overruns,
  cycle-timer discrepancies, errors, fatals, timeouts, or quantum changes.
  PipeWire remained at 48 kHz/128 frames, all four user audio services stayed
  active, Saffire routes remained connected, and AudioFire remained present
  with zero links.
- **2026-08-12:** Promote 128/3 to the current production configuration. Keep
  the validated 256/2 Home Manager generation as the rollback point. The
  existing allowance for one recoverable Ardour startup xrun still applies;
  steady-state operation must remain xrun-free.

### 2026-08-12 — delayed 128-frame failures and rollback

- A later audit found that 128/3 produced a second ringbuffer overflow and xrun
  at 11:06:31, 82 seconds after its first startup xrun and 22 seconds before the
  recorded CPU-load interval began. The clean load interval therefore did not
  qualify 128/3; it is superseded as a production choice.
- The 128/2 Home Manager generation built and activated successfully. Playback
  and microphone capture both worked normally, but the transport again wrote
  544 frames into a 511-frame ringbuffer and produced a second xrun at 11:15:25,
  about one minute after startup. The CPU load test was skipped because 128/2
  had already failed the steady-state acceptance criterion.
- The repository was returned to 48 kHz/256/2 with `ffado.rtprio = 92` and
  Ardour `PIPEWIRE_LATENCY=256/48000`. The check reused the validated
  `/nix/store/k3m4pq1hqx7alyab0137f6y5hlivhdaz-home-manager-generation`, which
  was activated successfully.
- Shutdown of the failed 128/2 process reached an unhandled FFADO xrun. After
  SIGTERM and SIGKILL, its main thread became a zombie while thread 27460
  remained uninterruptibly blocked in `fw_device_op_release`; PipeWire remains
  in `stop-sigkill` and cannot start the replacement. Do not repeat the earlier
  controller reset sequence, which failed to restore enumeration. Reboot the
  host with headphones at zero, then validate that 256/2 and both GUIDs return.
- **2026-08-12:** Reject both 128/3 and 128/2 for production. Restore 256/2 as
  the current configuration; the allowed single Ardour-startup xrun does not
  cover a second delayed xrun.
- The recovery reboot restored system generation 167 and Home Manager
  generation `k3m4pq1hqx7alyab0137f6y5hlivhdaz`. Both FireWire GUIDs returned,
  PipeWire runs at 48 kHz/256 frames, realtime ordering remains correct, all
  four audio services and the managed Saffire routes are active, and AudioFire
  has zero links. The user confirmed normal playback and microphone capture.
- Ardour startup nevertheless caused three xruns between 11:32:28 and
  11:32:35. Starting normal playback caused a fourth at 11:34:23; each had the
  same 544-frame write into a 511-frame ringbuffer. No further transport errors
  appeared after 11:34:24. Keep 256/2 active, but do not call the rollback fully
  requalified until longer normal use is clean.

### 2026-08-12 — AudioFire master-output route rejected

- The requested persistent route used the previously validated physical stereo
  mapping: Ardour Master 1 to AudioFire AUX0 (`Unknown_in`, left) and Master 2
  to AUX1 (`Unknown0_in`, right). The AudioFire capture node remained guarded
  against all links. The Home Manager check built successfully as
  `/nix/store/z95pdjjlrr8ml3c8pi362118bswsf91z-home-manager-generation`.
- Reloading WirePlumber created exactly those two AudioFire playback links and
  no capture links. AudioFire attempted to start at 11:42:00, reported a rate
  more than 10% off nominal, and released both isochronous channels by 11:42:03.
  At the same time, production Saffire playback overflowed its 511-frame
  ringbuffer and entered repeated timeouts, dead transmit handlers, alignment
  failures, and xruns every few seconds.
- WirePlumber was stopped before both AudioFire links were removed, preventing
  policy recreation. The route-policy source was returned to guarding both
  AudioFire nodes, the validated
  `/nix/store/k3m4pq1hqx7alyab0137f6y5hlivhdaz-home-manager-generation` rebuilt
  and activated, and WirePlumber restarted with zero AudioFire links.
- The Saffire transport did not recover after rollback. Its receive and
  transmit handlers remained dead or timed out, its managed routes could not
  be recreated, and stopping the damaged process risks the already-observed
  uninterruptible FireWire release hang. Reboot with both interfaces' output
  levels at zero; do not retain or automatically recreate this route.
- **2026-08-12:** Reject direct Ardour-master playback to the independently
  exported AudioFire in the current shared graph. Keep AudioFire present but
  unlinked until its failed concurrent-start behavior is diagnosed in a clean,
  isolated test.

### 2026-08-12 — Recovery after rejected AudioFire route

- A reboot with both automatic Ardour and AudioFire units disabled returned
  both FireWire GUIDs and a clean idle PipeWire/WirePlumber graph. Ardour was
  then started alone as transient unit `ardour-recovery.service`; all managed
  Saffire routes returned and AudioFire had zero links.
- Saffire startup produced one recoverable xrun at 12:06:34. The first physical
  playback test produced one more at 12:08:30, after which playback remained
  clean and the user confirmed normal stereo Firefox playback and microphone
  capture in Ardour.
- Restore the declarative Ardour and AudioFire services only with hardware
  output levels at zero. Keep the existing policy that exports AudioFire but
  prevents every automatic link to it.
- Reactivating the known-good Home Manager generation restored both declarative
  unit links. Replacing transient Ardour with managed Ardour caused four
  recoverable transition xruns from 12:10:10 through 12:10:32; all expected
  routes returned and no further transport error appeared after 12:10:33.
- Starting the managed AudioFire exporter at 12:11:04 published
  `audiofire_ffado_output` and `audiofire_ffado_input` in suspended state. Both
  have exactly zero links, and neither FFADO process logged an error after the
  exporter started.
- The final managed playback/capture check sounded correct, but first playback
  wrote 544 frames into FFADO's 511-frame ringbuffer and caused one recoverable
  xrun at 12:15:00. No audible fault remained. This repeats the bounded
  first-playback transition and is not a clean steady-state qualification.
- A later xrun appeared at 12:22:50 with no AudioFire links. FFADO timed out at
  12:23:20, both Saffire handlers died, and recovery reached fatal
  `Could not syncStartAll` at 12:23:26. This began before a temporary PipeWire
  loopback load was requested; no loopback nodes were created.
- **2026-08-12:** Reject 256/2 as a production setting. Prepare 512/2 for the
  next clean boot because AudioFire previously passed that setting for 30
  seconds with zero xruns; Saffire and the combined managed graph still require
  validation at 512/2.
- The focused Home Manager build for 512/2 passed as
  `/nix/store/bm91z47chm0l1lz06vcjrxnrq1mcz19i-home-manager-generation`.
  It is deliberately not activated against the failed live transport.
- After the recovery boot, both GUIDs returned and idle FFADO discovery was
  clean. A second 512/2 generation,
  `/nix/store/bas2qpmlqvk1r7vky9di9nfwjxh1j6xy-home-manager-generation`, was
  activated with AudioFire autostart removed for isolation. Home Manager did
  not restart the existing 256/2 PipeWire process.
- Managed Ardour briefly started that old process. It xrunned at 12:42:38 and
  hung while stopping at 12:42:41, before PipeWire could reload 512/2. Do not
  force the blocked teardown. Reboot once more: the active Home generation will
  then start directly at 512/2 with Ardour enabled and AudioFire stopped.

### 2026-08-12 — 512/2 and adaptive AudioFire bridge

- PipeWire started at 48 kHz/512/2 with AudioFire stopped. Managed Ardour
  created all expected Saffire routes and caused one recoverable startup xrun.
  First Firefox playback caused one more recoverable xrun after writing 544
  frames with 479 frames free. The user confirmed normal stereo playback and
  microphone capture; no later Saffire error appeared.
- AudioFire exported cleanly as two suspended nodes at 512/2. A temporary
  native PipeWire loopback connected Ardour Master L/R to the tested AudioFire
  AUX0/AUX1 outputs, placing a stream resampler between the independent device
  clocks. The Saffire remained running throughout.
- AudioFire crashed at the first playback start. Coredump PID 17794 shows its
  data thread in `ffado_streaming_transfer_playback_buffers` while the main
  thread was still reopening the device in `ffado_streaming_init`. Systemd
  restarted the exporter suspended; it was then stopped and every temporary
  bridge/link removed.
- Source inspection found that both FFADO filters can become streaming and
  schedule their process callbacks before synchronous `start_ffado_device()`
  finishes. Guard both playback and capture callbacks with `impl->started` so
  they cannot access the FFADO handle until prepare/start completes. The patch
  dry-applies to the exact PipeWire 1.6.8 source.
- The guarded PipeWire passed the full `deepthought` system build as
  `/nix/store/7q5syglb0dr5gci1yz62scwar81r3jz7-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  The matching Home generation, including the independent AudioFire host,
  built as `/nix/store/g554vpzc3nw9p9z47yqgmw5hlcl90cn5-home-manager-generation`.
- The guarded Home generation is active with Ardour and AudioFire stopped.
  System profile and systemd-boot default generation 168 both point to the
  guarded system; `/run/current-system` intentionally remains generation 167
  until reboot.
- After booting generation 168, the callback guard prevented the prior
  AudioFire crash. The adaptive bridge still could not start AudioFire
  playback: FFADO reported a measured rate of `626.52869`, more than 10% from
  the nominal 512-frame period, released its ISO channels, and left both
  AudioFire nodes idle. The Saffire remained alive.
- `ffado-test -p 0 BusReset` could not acquire the AudioFire while the
  production PipeWire process held FFADO discovery handles. Resetting only PCI
  function `0000:06:00.0` while that process was live is rejected: despite the
  separate controllers, the one FFADO process also held the Saffire controller
  and entered an unbounded sequence of negative cycle-timer corrections.
- A complete userspace audio-stack restart required systemd to kill the stuck
  PipeWire process after its stop timeout. The replacement initialized, but
  starting Ardour reactivated the negative cycle-timer sequence. Stop Ardour,
  PipeWire, PipeWire Pulse, WirePlumber, and both activation sockets before
  recovering the kernel FireWire state. With no FFADO process remaining,
  unbind and rebind both `firewire_ohci` PCI functions (`0000:06:00.0` and
  `0000:07:00.0`) before restarting the stack. The user explicitly approved a
  complete audio-stack restart for this work.
- Rebinding both idle controllers cleared the corrupted kernel clock. The
  production stack returned at 512/2, Ardour restored every managed Saffire
  route, and FFADO had one bounded startup xrun. The first subsequent playback
  transition had one more bounded xrun; no later Saffire error appeared.
- Retrying the guarded adaptive bridge after that reset again failed AudioFire
  playback, this time at a measured rate of `627.47986`. FFADO released its ISO
  channels, the AudioFire nodes returned idle, the callback guard prevented a
  crash, and the Saffire remained running. The bridge was removed and the
  AudioFire exporter stopped.
- The first isolated control test was contaminated by launching the normal
  WirePlumber profile, which also enumerated ALSA, Bluetooth, and video
  hardware. Silent playback entered FFADO startup but did not complete, and
  teardown deadlocked until the test process was killed. A transient USB wait
  from the unwanted ALSA devices initially obscured the FFADO threads. Do not
  treat this run as a clean shared-graph discriminator; repeat it with the
  previously validated policy-only WirePlumber profile.
- The policy-only retry was clean: AudioFire playback started in a fully
  isolated 512/2 graph, then simultaneous capture joined it. Both FFADO nodes
  remained running with the expected direct stereo links and no AudioFire
  error. This proves the exported shared graph, not baseline AudioFire duplex,
  causes the initial bridge failure.
- AudioFire did not survive an idle-to-running lifecycle transition. After the
  direct test clients disconnected, the next client start measured `626.57025`
  frames against nominal 512 and released both ISO channels. Production
  Saffire had one bounded xrun during that failed transition and then remained
  stable. The isolated process deadlocked during teardown and was killed.
- Keep AudioFire in its independent graph and use a local Pulse tunnel for the
  stereo cross-clock boundary. While the AudioFire service is enabled, keep
  its playback stream continuously active instead of repeatedly stopping and
  reopening FFADO. Test this only after an AudioFire-only power cycle gives the
  tunnel a fresh first start.
- The first fresh Pulse-tunnel attempt activated Ardour Master left before its
  right link existed. AudioFire immediately reproduced the invalid-rate abort
  at `627.32825`, then a retry could not prepare its already-enabled ports.
  This repeats the known incremental-link failure mode; the isolated process
  subsequently exited cleanly. On the next fresh start, create the left link
  passive and use the right link as the single activation event.
- A fresh retry showed the Pulse tunnel activates its remote stream when the
  module loads, before either local Ardour link; making the first local link
  passive therefore cannot affect AudioFire startup. Its remote node correctly
  requested 48 kHz and `512/48000` latency, but negotiated `s16le`, while the
  successful isolated `pw-cat` client used float32. Force `audio.format =
  F32LE` on the next fresh tunnel before rejecting this transport.
- Forcing `F32LE` did not help; AudioFire aborted at `625.73590`. Inspection
  then showed the actual behavioral difference: the tunnel's remote Pulse
  stream was uncorked and running before the local tunnel sink had any Ardour
  links, whereas the successful direct client continuously supplied zeros.
  Configure the local tunnel with `node.pause-on-idle = true`, create its left
  link passive, and use the right link to activate the complete stereo path.
  This should prevent the remote stream from starting without a producer.

### 2026-08-12 — Pulse tunnel validated, permanent two-graph design rejected

- PipeWire's Pulse tunnel created its remote playback stream before the local
  sink had a producer. A one-line test patch added `PA_STREAM_START_CORKED` so
  the remote stream remained corked until the local stream became active.
- With the patched tunnel, the first Ardour link was created passively and the
  second link activated the complete stereo route. The AudioFire started once,
  remained active, and the adaptive rate control converged. The user confirmed
  normal physical playback from the AudioFire. This proves that the two
  independent hardware clocks can be bridged reliably when startup supplies a
  complete stream before FFADO begins.
- The user rejected an isolated AudioFire graph plus Pulse tunnel as the
  permanent architecture. Keep the working processes alive only as a temporary
  reference until a single-graph replacement is ready to test.

### 2026-08-12 — Single-graph architecture correction

- PipeWire supports multiple driver nodes in one core. The FFADO module marks
  every source and sink as a driver with `PW_FILTER_FLAG_DRIVER`; driver
  priority therefore cannot turn the AudioFire into an ordinary follower.
- FFADO accepts multiple device specifications and can expose them as one
  pseudo-device, but its API explicitly requires those devices to be linked in
  one synchronization domain. The Saffire and AudioFire currently use
  independent internal clocks, so one FFADO instance containing both GUIDs is
  rejected unless a physical digital-clock connection is added and validated.
- PipeWire's stream nodes contain adaptive resamplers and its combine/loopback
  modules use asynchronous streams on the hardware-facing side. This permits
  the Saffire and AudioFire to remain separate graph drivers while a stream
  absorbs their clock drift inside one production graph.
- The earlier native loopback experiment did not establish that this design is
  invalid. `libpipewire-module-loopback` sets `resample.disable = true` when no
  `audio.rate` is supplied, and that experiment also activated the AudioFire
  during an incomplete startup. Both conditions conflict with what the
  successful Pulse test proved is required.
- **Decision:** replace the Pulse tunnel with a production-core native combine
  sink at 48 kHz, explicitly set `resample.disable = false`, and dynamically
  create its passive playback stream only when `audiofire_ffado_output`
  appears. Keep Ardour's direct Saffire route unchanged. Run the combine sink
  continuously so it is already producing silence before the AudioFire starts
  and so an Ardour restart cannot cycle the known-fragile FFADO transport.
- The separate `audiofire-ffado-host` process may remain as a crash-isolation
  boundary, but its FFADO filters use `remote.name = pipewire-0`; therefore the
  AudioFire processing nodes and adaptive stream belong to the production
  graph, not to the host process's otherwise empty local core.
- The first implementation uses stock `libpipewire-module-combine-stream`,
  matches only `audiofire_ffado_output`, maps FL/FR to AUX0/AUX1, and explicitly
  enables its 48 kHz stream resampler. The focused Home Manager build passed as
  `/nix/store/b8cv7yg53v4d55lsxvfyxky1hgf3c7ad-home-manager-generation`; it is
  not active yet.
- A separate-runtime configuration parse and four-second PipeWire startup
  passed. A follow-up port-alias probe mistakenly launched WirePlumber's normal
  hardware profile instead of the intended policy-only profile. That probe was
  stopped, but immediately afterward the production Saffire began repeated
  FFADO xruns and `syncStartAll` failures. Treat the timing as correlated, not
  proven causation. Do not activate or test the new graph until the complete
  audio stack and both FireWire controllers have been reset.

### 2026-08-12 — AudioFire deferred; return to Saffire-only 256/2

- The user decided the AudioFire is not important enough to justify further
  multi-clock work now and physically disconnected it. Supersede the pending
  combine-stream cutover with a Saffire-only production graph.
- Remove the unactivated AudioFire combine module and Ardour-to-combine routes.
  Restore the routing guard for both AudioFire nodes and keep the exporter
  disabled by leaving it without an install target.
- Restore PipeWire, the Saffire FFADO period, the dormant AudioFire test config,
  and Ardour's requested latency to 48 kHz/256/2.
- The failed controller-unbind shell remains stuck in the current kernel after
  both physical devices were removed. Do not attempt more recovery in this
  boot. Reboot only after the Saffire-only Home Manager generation is built and
  linked; reconnect only the Saffire for post-boot validation.
- The focused Saffire-only Home Manager build passed as
  `/nix/store/0qh5rjalw8833iz9scbnl6a58ab4k0n7-home-manager-generation` and is
  the current Home Manager profile. Its installed PipeWire drop-in requests
  256 frames at 48 kHz with two FFADO periods, Ardour requests `256/48000`, and
  no AudioFire combine drop-in exists. The exporter is linked but not enabled;
  Ardour remains enabled for the desktop session.
- Home Manager linked every file before its service switch encountered the
  intentionally unavailable audio stack. The residual Ardour readiness job
  was stopped. Audio units are runtime-masked only for this broken boot; those
  masks live under `/run/user/1000` and disappear on reboot.

### 2026-08-12 — post-reboot Saffire hang diagnosis

- The clean boot started PipeWire at 48 kHz/256/2 with only the Saffire
  physically connected. FFADO overflowed its 511-frame receive ring nine times
  in eight minutes. The ninth recovery killed first the receive and then the
  transmit handler before failing fatally with `Could not syncStartAll` and
  `ffado_streaming_wait: Error condition while waiting (Unhandled XRUN)`.
- PipeWire's control plane remained responsive and all clients and links stayed
  registered, but both FFADO nodes stopped producing periods. No FireWire bus
  reset or other kernel event accompanied the failure.
- The hardware and scheduler state matched the validated setup: the Saffire is
  on controller `07:00.0`, its IRQ 39 runs FIFO 94, FFADO transmit/ARM/receive
  run FIFO 93/92/91, PipeWire's data loop runs FIFO 88, and all CPU governors
  report `performance`.
- The reboot was not actually a clean Saffire-only configuration. An orphaned
  `~/.config/pipewire/pipewire.conf.d/21-audiofire-combine.conf` symlink from an
  older Home Manager generation remained alongside the new generation's three
  drop-ins. PipeWire consequently loaded `libpipewire-module-combine-stream`;
  its `audiofire_master` node is running with `node.always-process = true` and
  is driven by `saffire_ffado_input`, though it has no AudioFire stream or
  links. Remove this stale managed-file link before the next qualification.
- The immediate hang mechanism is established: PipeWire stopped draining the
  FFADO receive path long enough to fill its ringbuffer, after which libffado's
  xrun recovery repeatedly attempted to enable an already-enabled receive
  stream and could not restart the synchronization domain. The initial reason
  for the missed graph periods is not yet isolated. The stale combine node
  invalidates this run but is not proven causal because the same delayed
  `544,511` overflow occurred before the combine module was introduced.

### 2026-08-12 — 1024/3 recovery deployment

- Supersede 256/2 as the recovery setting. Production PipeWire and the Saffire
  FFADO module now request 48 kHz/1024 frames/three periods, and Ardour requests
  the matching `PIPEWIRE_LATENCY=1024/48000`. The dormant AudioFire test
  configuration remains unchanged.
- The focused Home Manager activation package built successfully as
  `/nix/store/39w71va6hdbh2b6vcy9gzfx80jkjfxjl-home-manager-generation` and is
  the active Home Manager profile. Inspection of the built generation confirms
  it contains only `10-null-sink.conf`, `11-null-source.conf`, and
  `20-firewire-ffado.conf` under PipeWire's drop-in directory.
- Home Manager did not remove the old
  `21-audiofire-combine.conf` link because it was left outside the current
  generation's managed link set. The exact orphaned link was removed manually;
  the installed PipeWire drop-in directory now matches the built generation.
- Ardour, WirePlumber, and PipeWire Pulse stopped cleanly. The failed PipeWire
  process timed out while stopping FFADO and systemd sent SIGKILL after 90
  seconds. Its main thread became a zombie while FFADO bus-reset thread 7504
  remained uninterruptibly blocked in `fw_device_op_release`, leaving
  `pipewire.service` in `stop-sigkill`. Do not attempt a controller reset or
  driver unbind in this kernel; reboot is the recovery boundary.
- After reboot, first verify that no combine module or AudioFire node exists,
  then confirm 1024-frame PipeWire timing, physical playback, microphone
  capture, and a clean xrun baseline before beginning the one-hour normal-use
  soak.

### 2026-08-12 — 1024/3 rejected; restore Saffire 512/2

- The reboot produced the intended clean graph: one GUID-bound Saffire FFADO
  module, no AudioFire or combine module, and a live PipeWire clock fixed at
  48 kHz/1024 frames. Realtime scheduling was also correct: FireWire IRQs ran
  FIFO 95/94, FFADO transmit/ARM/receive ran FIFO 93/92/91, and PipeWire's data
  loop ran FIFO 88.
- Despite that clean state, FFADO recorded 11 xruns in roughly the
  first four minutes of streaming. Receive and transmit handlers repeatedly
  exceeded libffado's 49.152 ms death threshold, entered timeout and
  `syncStartAll` recovery, and produced multi-second audio interruptions. The
  stream sometimes recovered, including after a YouTube ad boundary, but did
  not meet the no-steady-state-xrun criterion.
- **Decision:** reject 1024/3 for the Saffire. Buffer size is not monotonic for
  this FFADO path, and 1024/3 is substantially worse than the previously tested
  512/2 configuration. Restore PipeWire, Saffire FFADO, and Ardour latency to
  48 kHz/512/2. Do not add an automatic restart watchdog: a failed FFADO close
  can block uninterruptibly in the kernel, so a watchdog would hide the fault
  without reliably recovering it.
- The current 1024/3 process is already damaged. Build and activate the 512/2
  Home Manager generation, but use a reboot as the transport recovery boundary
  rather than forcing another FFADO teardown or PCIe controller reset.
- The focused 512/2 Home Manager generation built successfully as
  `/nix/store/3qhw5l6qaxdn2f7hsfb10hixiiv8w4gw-home-manager-generation` and is
  the active profile. It was activated with the user systemd bus deliberately
  unavailable, so Home Manager installed the 512/2 PipeWire drop-in and
  Ardour's `PIPEWIRE_LATENCY=512/48000` without restarting the live 1024/3
  process. Reboot remains the next and only recovery action.

### 2026-08-12 — PipeWire xrun-recovery root-cause test

- The clean 512/2 boot streamed normally through the ad-to-video transition,
  then stopped during sustained video playback. PipeWire logged four graph
  xruns, both FFADO handlers died, and libffado failed recovery with
  `requestEnable: Enable requested on enabled stream 'Receive'` followed by
  fatal `Could not syncStartAll`. The FFADO process retained only its main and
  non-streaming threads afterward.
- JACK2's FFADO driver is the behavioral control. It waits for a period,
  transfers capture, runs the graph, transfers playback, and treats
  `ffado_wait_xrun` as a recoverable skipped cycle. PipeWire follows the same
  broad sequence, and libffado 2.5.0's `ffado_streaming_reset()` is a no-op, so
  neither the retry loop nor that reset explains the divergence.
- PipeWire's FFADO source callback is the only hardware-driver path in the
  tree that returns immediately when `SPA_IO_CLOCK_FLAG_XRUN_RECOVER` is set.
  The flag means the node missed its previous graph deadline and is being
  called so it can resynchronize. Returning performs no capture transfer, no
  fallback playback transfer, and no period completion; the module leaves its
  one-second watchdog armed while FFADO's receive buffer continues filling.
  The observed `PipeWire` xrun counter increments before each FFADO recovery
  cascade, matching this control flow.
- **Decision:** keep FFADO and test the minimal root-mechanism change: remove
  the `XRUN_RECOVER` early return so the callback drains and completes the
  current FFADO period. Carry it as a separate one-hunk patch during
  qualification so the independently prepared upstream lifecycle patch is
  unchanged. Test at the JACK-equivalent target of 48 kHz/128/3; 256/2 remains
  an acceptable fallback only if 128/3 produces excessive but recoverable
  xruns.
- The focused PipeWire package, complete deepthought NixOS system, and Home
  Manager generation all build successfully. The resulting system is
  `/nix/store/nmi9z2a7j3bfb05wk4fqinpac6d46cvk-nixos-system-deepthought-26.05.20260809.fcb8fcd`;
  the Home Manager generation is
  `/nix/store/bh7b8r57fjlqhq0jvxm7g18jajy7dxjr-home-manager-generation`.
  Home Manager was activated with its systemd bus deliberately unavailable,
  installing the 128/3 configuration without restarting the failed live
  transport.
- NixOS generation 169 is staged as the system profile and systemd-boot entry;
  its kernel command line points to the expected patched system store path.
  The live generation was not switched. A clean reboot is the remaining
  deployment boundary.
- Generation 169 booted with the patched PipeWire store path and the graph at
  48 kHz/128 frames. Ardour initially paused at its crash-recovery prompt, so
  its partial graph was not a transport failure. After recovery, Ardour
  restored its master outputs to both Saffire playback channels, Saffire input
  1 to the microphone track, and the normal application buses. No xrun or
  fatal FFADO message was logged before playback qualification began.
- The first boot transport nevertheless had a zero-rate graph: FFADO's
  transmit and receive threads existed, but `pw-top` reported quantum and rate
  zero for every node, so neither Firefox playback nor microphone capture
  advanced. Stopping Ardour then exposed continuous FFADO event-buffer
  overruns; PipeWire wedged in a realtime mutex and required `SIGKILL`. This is
  a failed recovery/teardown case, not a routing failure.
- A controlled full PipeWire/FFADO restart with the same 128/3 configuration
  started a live 128-frame, 48 kHz graph. Under temporary debug logging it
  reported two FFADO xruns with zero PipeWire xruns; both were recoverable and
  the graph continued advancing. Broad debug logging was then disabled before
  playback qualification because its journal load would distort the latency
  test.
- After Ardour restored the complete graph, a third FFADO xrun recovered but a
  fourth reached fatal `Could not syncStartAll`; all FFADO streaming threads
  exited and `pw-top` returned to a zero-rate graph. The first recovery patch
  therefore fixed the immediate PipeWire deadlock but was incomplete.
- JACK's FFADO driver skips all buffer transfers after a handled xrun and
  immediately retries `ffado_streaming_wait()`. PipeWire's original
  `XRUN_RECOVER` guard skipped the transfers but failed to complete/re-arm its
  cycle; deleting the guard instead allowed transfers from a recovery cycle.
  **Decision:** retain the guard, mark that skipped cycle done, and re-arm the
  FFADO timer immediately. This is the smallest behavior that matches JACK
  without transferring stale recovery buffers.
- The rejected process again left its main thread a zombie and one libffado
  watchdog thread uninterruptibly blocked in `fw_device_op_release` on the
  Saffire's `07:00.0` controller. Signals cannot clear a D-state thread, and
  the earlier controller-reset sequence was already rejected as unreliable;
  reboot remains the recovery boundary. The refined patch passed the focused
  PipeWire build and the complete deepthought build as
  `/nix/store/gfv0wr5r9gcbdrh1s8x69xsdd3nh8cmp-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  That store path is staged as NixOS generation 170 and its systemd-boot entry
  points to the expected init path.

### 2026-08-13 — Secondary FireWire IRQ priority experiment

- Generation 170 booted with the refined recovery patch and a live 48 kHz,
  128-frame graph. During Ardour startup, FFADO's transmit ISO handler first
  timed out and died at 00:03:22. Four more transmit deaths and one receive
  death followed before fatal `Could not syncStartAll` at 00:03:43. The
  recovery path again tried to enable the already-enabled receive stream and
  left the graph unable to carry playback or capture.
- Every reported recovery retained `PipeWire:0`; the first failure happened in
  FFADO's ISO handling rather than after a PipeWire graph deadline. The
  `XRUN_RECOVER` source callback therefore did not participate. Remove the
  separate `xrun-recovery.patch` rather than carrying a disproven behavioral
  change. PipeWire master has no existing FFADO lifecycle or transfer fix that
  addresses this sequence.
- The live thread hierarchy exposed an untested priority inversion. rtirq
  raised only the primary FireWire threads to FIFO 95 and 94. On this
  PREEMPT_RT kernel each controller also has a forced secondary IRQ thread,
  `irq/*-s-firewi`, still at FIFO 50. FFADO's transmit, ARM, and receive threads
  run at FIFO 93, 92, and 91, so they can preempt the secondary kernel handler
  that runs the driver's original threaded interrupt function. JACK's default
  graph/FFADO priorities of 10 and 15 (workers 16/15/14) remain below that
  secondary IRQ thread.
- **Decision:** keep PipeWire/FFADO at 48 kHz/128/3 and make one scheduling-only
  experiment. Set musnix rtirq `highList = "s-firewi"` so both secondary
  FireWire IRQ threads are raised above FFADO. Do not simultaneously
  change PipeWire or FFADO priority; this isolates whether missed secondary
  IRQ service caused the ISO inactivity. A valid post-boot test must first
  confirm both secondary threads outrank FFADO, then exercise playback,
  microphone capture, Ardour graph startup, application stop/start, and
  sustained playback. Recovered xruns are informational; only a wedged graph,
  dead FFADO handler, unrecovered audio failure, or stuck teardown rejects the
  setting.
- The complete deepthought build passed as
  `/nix/store/c2rdgmqffls46cbhlzi6awapnjp0slfi-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  Its generated `rtirq.conf` contains `RTIRQ_HIGH_LIST="s-firewi"`, and its
  PipeWire derivation carries only `ffado-driver.patch`; the rejected recovery
  patch is absent. Stage this generation with `nixos-rebuild boot`, not
  `switch`, because the live FFADO transport is already damaged.
- NixOS generation 171 is staged as the system profile and systemd-boot
  default. Its boot entry points to the verified `c2rdgm...` system path. The
  live generation was not switched; reboot is the remaining deployment
  boundary.
- Generation 171 booted successfully. rtirq raised both forced secondary
  FireWire IRQ threads to FIFO 99; the primary controller IRQs are FIFO 95 and
  94, FFADO transmit/ARM/receive are FIFO 93/92/91, and PipeWire's data loop is
  FIFO 88. Both secondaries therefore outrank the FFADO packetizer threads as
  intended.
- Ardour paused at its crash-recovery dialog while loading the Default session.
  After the user selected recovery, every managed Saffire route appeared and
  the graph ran at 48 kHz/128 frames. Completing recovery caused one bounded
  ringbuffer overflow and one FFADO/PipeWire xrun at 09:32:34; the graph
  continued afterward. A second ringbuffer overflow and recovered xrun occurred
  at 09:34:37, roughly two minutes later, and a third recovered at 09:40:09.
  None killed a handler or stopped the graph. The user subsequently relaxed the
  acceptance rule: remain at 128/3 and treat xruns as informational unless they
  wedge the graph or lead to another catastrophic transport failure.
- Ardour 9.7 has no command-line option, preference, or environment variable to
  always accept pending session state. Its GUI directly connects the pending
  state query to the crash-recovery dialog. A local one-line package patch was
  considered and its build started, then cancelled and removed because carrying
  an Ardour fork solely for this policy is not presently acceptable. Do not
  replace it with GUI input automation or pre-launch session-file mutation; if
  automation becomes necessary, propose a supported `--recover` option
  upstream.

### 2026-08-13 — Graph-xrun recovery failure under generation 171

- Before the transport failure, the Saffire hardware path was independently
  verified. A temporary direct Firefox-to-Ardour-Master connection was audible,
  while a capture probe showed real signal at the Ardour Firefox strip output
  and digital silence at the Master output. This isolates the earlier silence
  to Ardour's recovered internal strip-to-Master routing, not FFADO playback or
  capture. The direct connection disappeared when Firefox recreated its stream.
- A temporary native PipeWire loopback was then used to test an external bridge
  around Ardour's same-client feedback links. Activating it caused an ordinary
  graph xrun; the loopback and all of its links were removed, but the FFADO
  transport did not recover. Do not retain this workaround.
- The fatal sequence began at 09:52:55 with a 544/511 receive-ring overflow and
  a handled FFADO xrun. PipeWire then reported `FFADO:4 PipeWire:4`; exactly one
  second later it counted another PipeWire xrun, libffado reconstructed invalid
  cycle timers and calculated a rate near 967 instead of its nominal 512, and
  both ISO handlers subsequently died. Recovery ended in repeated
  `requestEnable` errors and fatal `Could not syncStartAll`. There was no kernel
  FireWire bus reset or controller error in this interval. The live graph now
  reports zero quantum/rate for every running node.
- This is distinct from generation 170's scheduling failure. That boot died
  below the graph with `PipeWire:0`, so it did not exercise the refined
  `XRUN_RECOVER` callback at all. Generation 171 proves the IRQ change does not
  solve graph-xrun recovery, but does not disprove that callback fix.
- JACK's FFADO driver handles `ffado_wait_xrun` by returning zero frames and
  immediately retrying `ffado_streaming_wait()`, without capture, graph, or
  playback transfer for the bad period. PipeWire's source callback likewise
  skips transfers when `SPA_IO_CLOCK_FLAG_XRUN_RECOVER` is set, but originally
  returns without setting `impl->rt.done` or re-arming its timer. Its existing
  one-second watchdog therefore expires while the FFADO receive ring continues
  to fill. The observed one-second delay and simultaneous PipeWire/FFADO xrun
  counters match this path exactly; `ffado_streaming_reset()` cannot help
  because it is a no-op in libffado 2.5.0.
- **Decision:** do not change the sample rate, quantum, or period count. Retain
  48 kHz/128/3 and the secondary IRQ boost, and restore the minimal refined
  patch that marks a skipped recovery cycle done and immediately re-arms the
  FFADO timer. This combines fixes for the two independent failure modes. Build
  and stage it for a clean reboot; do not force teardown of the damaged live
  FFADO process.
- The complete combined system built successfully as
  `/nix/store/gddafcgn3c64qgmpqpzpmkm172x08qps-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  Its PipeWire derivation contains both `ffado-driver.patch` and
  `xrun-recovery.patch`, and its generated rtirq configuration retains
  `RTIRQ_HIGH_LIST="s-firewi"`. NixOS generation 172 is the system profile and
  systemd-boot default; its boot entry points to the verified system init.
- Generation 172 booted the intended combined build, but failed below the
  PipeWire graph during Ardour startup. From 10:18:13 through 10:19:00 the
  transmit handler repeatedly died, the receive handler followed, and all
  reported recoveries remained `PipeWire:0`. Recovery ended in fatal
  `Could not syncStartAll`; the graph returned to zero quantum/rate and the
  microphone meter stopped. The `XRUN_RECOVER` patch did not participate.
- Correct the earlier interpretation of FFADO's handler deadline: its
  `49152000` counter is in 24.576 MHz FireWire ticks and represents two seconds,
  not 49.152 ms. Linux RT bandwidth throttling is therefore not indicated by
  this timing; the live kernel also retained its default 950000/1000000 quota.
- The known JACK/FFADO control used JACK priority 88, FFADO base priority 93
  (transmit/ARM/receive 94/93/92), and both primary FireWire IRQ threads at 99.
  The failed PipeWire boot instead used graph 88, FFADO base 92
  (93/92/91), primary IRQs 95/94, and secondary IRQs 99. PCI runtime power was
  forced on, the Saffire remained on its tested `07:00.0` controller, and no
  kernel bus reset or PCI error accompanied the failure.
- **Decision:** keep 48 kHz/128/3 and reproduce the known-good JACK scheduling
  hierarchy exactly. Set `ffado.rtprio = 93` and put both `firewire_ohci` and
  `s-firewi` in rtirq's high list so all primary and forced-secondary FireWire
  IRQ threads precede FFADO. This is the next scheduling experiment; do not
  change buffer or period settings.
- The focused Home Manager generation built and was activated with user systemd
  deliberately unavailable, so it installed `ffado.rtprio = 93` without
  restarting the failed live transport. The complete NixOS system built as
  `/nix/store/yg18810siad6phnazhq8w3x16vn9kp2h-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  It is staged as generation 173 and is the systemd-boot default. Reboot is the
  remaining deployment boundary.
- Generation 173 booted with the intended JACK-like priority hierarchy: the
  primary FireWire IRQ threads ran at FIFO 99, the secondary FireWire IRQ
  threads at 98, FFADO transmit/ARM/receive at 94/93/92, and the PipeWire graph
  at 88. Ardour startup still killed the transmit handler within seconds; the
  receive handler followed and FFADO ended in fatal `Could not syncStartAll`.
  The graph returned to zero quantum/rate and microphone capture stopped.
- **Correction:** the `PipeWire:0` counter on generations 170, 172, and 173 did
  not prove that the refined recovery callback was unused. That patch marked
  the cycle done before the one-second watchdog could increment the counter,
  while still skipping both FFADO transfers. Repeated recovery callbacks could
  therefore starve the hardware queues invisibly until the ISO handlers hit
  their two-second inactivity threshold. The exact JACK-like priority test
  rules out the three tested IRQ/FFADO priority layouts as the primary cause.
- The callback before the 2024 `XRUN_RECOVER` early return already distinguishes
  real FFADO wakeups from synthetic callbacks with `impl->rt.triggered`. On a
  real wakeup it clears the trigger and transfers capture; on a synthetic call
  it completes/re-arms the period and supplies fallback playback silence when
  needed. **Decision:** remove only the unconditional `XRUN_RECOVER` return so
  this established state machine runs. Keep the generation 173 priorities and
  48 kHz/128/3, producing a single-variable recovery experiment. This revisits
  the generation 169 patch under the subsequently corrected scheduling layout.
- The revised patch applies cleanly to current PipeWire master. The complete
  deepthought system built successfully as
  `/nix/store/rzczcz03qifnbcpzcdb38hmrzavin6pb-nixos-system-deepthought-26.05.20260809.fcb8fcd`,
  and the matching Home Manager generation built as
  `/nix/store/5ibmr4w9dj6vhqlsan9b81npnkpwgcqw-home-manager-generation`.
  Home Manager was activated with its systemd bus deliberately unavailable, so
  it installed the new PipeWire package and verified 48 kHz/128/3 with
  `ffado.rtprio = 93` without restarting the dead live transport. The system
  build is staged as NixOS generation 174 and is the systemd-boot default; its
  boot entry points to the verified `rzczcz03...` init path. Reboot is the
  remaining deployment boundary.
- Generation 174 booted the verified system and started the Saffire at
  48 kHz/128 frames. The live hierarchy matches the intended control: primary
  and secondary FireWire IRQs at FIFO 99/98, FFADO transmit/ARM/receive at
  94/93/92, and PipeWire at 88. Ardour restored its Saffire playback and
  microphone links. One startup ring overflow produced `FFADO:1 PipeWire:1`;
  it recovered, both ISO handlers remained alive, and the driver continued
  advancing at 48 kHz/128. Physical playback and capture qualification remain.
- Physical qualification rejected that recovery behavior. Ardour's microphone
  meter was silent, and direct ten-second recordings first from the routed
  input and then from all 16 FFADO capture channels contained only zero samples.
  Both recorders also needed roughly 20 seconds to accumulate ten seconds of
  nominal 48 kHz samples. The ISO threads remained alive and no later xrun was
  reported: this was a false-running, desynchronized transport rather than a
  routing error.
- Ardour's missing strip-to-Master routes were independently traced to the
  stale `Default.pending` crash-recovery file. It contained duplicated
  `ardour:ardour:` port prefixes and omitted the internal connections, while
  the saved `Default.ardour` retained all correct routes. The pending file was
  preserved as `backup/Default.pending.gen174-silent-capture`; relaunching the
  saved session restored every internal route without a recovery prompt.
- A controlled stack restart reproduced the known teardown defect: after
  Ardour stopped, FFADO's capture event buffer overran continuously and
  PipeWire waited on an RT mutex until systemd's 90-second timeout sent
  `SIGKILL`. No old thread survived, and the replacement daemon reopened the
  Saffire. Ardour then reproduced the same 544/511 startup overflow and
  `FFADO:1 PipeWire:1` recovery on the clean stack.
- **Decision:** the deleted `XRUN_RECOVER` guard is wrong because it can consume
  a stale hardware trigger and transfer buffers during PipeWire's synthetic
  recovery callback. The refined skip-and-rearm version was also incomplete:
  it left `impl->rt.triggered` set, so a later normal callback could still
  consume the stale period. Match JACK's skipped-cycle behavior by clearing
  `rt.triggered`, marking the period done, and rearming the FFADO wait without
  transferring either buffer. This is one additional state assignment over
  the refined patch; retain 48 kHz/128/3 and the generation 174 priorities.
- The clear-trigger patch applies cleanly to current PipeWire master. The full
  system built successfully as
  `/nix/store/i28r0mm3pg39ghyc556bgj71h0av41m4-nixos-system-deepthought-26.05.20260809.fcb8fcd`,
  and Home Manager built as
  `/nix/store/9q77r1axig8i12csbg5iaailwhiar2ma-home-manager-generation`.
  Home Manager was activated with its systemd bus deliberately unavailable,
  installing the matching package without reloading the live audio services.
  The system build is staged as NixOS generation 175 and is the systemd-boot
  default; its boot entry points to the verified `i28r0mm...` init path. Reboot
  is the remaining deployment boundary; do not test through another live
  teardown.
- Generation 175 rejected the clear-trigger recovery immediately. After the
  first `FFADO:1 PipeWire:1` event, the transmit handler died about every four
  seconds; FFADO reached 13 xruns, the receive handler then died, and recovery
  ended in fatal `Could not syncStartAll`. The graph is at zero rate. Clearing
  the trigger while transferring neither direction therefore starves the
  outstanding FFADO hardware period; do not retain this variant.
- The earlier delete-guard variant transferred capture but could let the graph
  submit stale playback. The refined skip variant transferred neither direction
  and produced a false-running silent graph. **Decision:** service the recovery
  period explicitly: clear the stale trigger, drain capture into FFADO's port
  buffers, submit silence only if the sink has not already transferred, and use
  the existing `complete_period()` helper. This keeps both hardware queues
  moving without publishing stale capture or stale graph playback. It is the
  final minimal combination of the module's existing recovery primitives.
- The drain-and-silence patch applies cleanly to current PipeWire master. The
  full system built successfully as
  `/nix/store/k9kj586jffqmgqz6l890xq861ipa9f8a-nixos-system-deepthought-26.05.20260809.fcb8fcd`,
  and Home Manager built as
  `/nix/store/gvraz2q0isa4lskw8ah1b0rmy4yvf1mk-home-manager-generation`.
  Home Manager was activated with its systemd bus deliberately unavailable,
  installing the matching package without reloading the dead live transport.
  The system build is staged as NixOS generation 176 and is the systemd-boot
  default; its entry points to the verified `k9kj586...` init path. Reboot is
  the remaining deployment boundary.
- Generation 176 rejected the unconditional drain-and-silence variant. It
  entered an xrun roughly once per second after the first recovery; the receive
  handler died first, the transmit handler followed, and FFADO ended in fatal
  `Could not syncStartAll` with a zero-rate graph. This is consistent with
  transferring capture twice when the source callback had already run before
  PipeWire forced the recovery callback.
- PipeWire 1.6's scheduler already includes all active nodes sharing
  `node.group`, so the later upstream group-scheduling change is not missing
  from this build. **Decision:** condition the recovery capture drain on
  `impl->rt.triggered`. A true value means the source callback never serviced
  the outstanding hardware period; false means capture was already transferred
  and only a missing playback transfer may need silence. In both cases use the
  existing transfer flags and `complete_period()` to finish exactly once.
- The state-aware patch applies cleanly to current PipeWire master. The full
  system built successfully as
  `/nix/store/2r2q2yzzdw40513c1448gv3kpmx83ip6-nixos-system-deepthought-26.05.20260809.fcb8fcd`,
  and Home Manager built as
  `/nix/store/cp71p3k6md55w2ddbhck3086m6rayb86-home-manager-generation`.
  Home Manager was activated with its systemd bus deliberately unavailable,
  installing the matching package without reloading the dead transport. System
  staging is complete as NixOS generation 177; it is the systemd-boot default
  and points to the verified `2r2q2yz...` init path. Reboot remains.
- Generation 177 rejected the state-aware recovery variant. The first recovery
  occurred about 7.3 seconds after FFADO streaming started. Both ISO handlers
  remained alive and the source driver continued at 48 kHz/128 frames, but the
  downstream PipeWire error counters then increased on every cycle and FFADO
  emitted continuous reconstructed-CTR discrepancies. A direct 10-second,
  16-channel `pw-record` completed in real time with exactly 480,000 frames,
  but every sample on every channel was bit-for-bit zero. The recovery branch
  therefore completes PipeWire periods without publishing capture and leaves
  the graph permanently in synthetic recovery; a live thread and advancing
  clock are not sufficient qualification.
- **Decision:** retry normal source callback processing during
  `SPA_IO_CLOCK_FLAG_XRUN_RECOVER` by removing the upstream early return. This
  is the only variant that previously returned the graph to real capture data.
  Its earlier generation-169 failure predates the corrected IRQ/FFADO/graph
  priority hierarchy, so that result does not distinguish callback behavior
  from priority inversion. Keep 48 kHz/128/3 and all corrected priorities
  unchanged; this experiment changes only the recovery guard. If it still
  kills an ISO handler, stop trying recovery-policy permutations and add
  narrowly scoped state tracing around the first recovery.
- The normal-callback variant is byte-for-byte identical to the earlier
  generation-174 build. Nix reused
  `/nix/store/rzczcz03qifnbcpzcdb38hmrzavin6pb-nixos-system-deepthought-26.05.20260809.fcb8fcd`
  and
  `/nix/store/5ibmr4w9dj6vhqlsan9b81npnkpwgcqw-home-manager-generation`.
  The Home Manager generation is active. Its activation script discovered the
  real user bus despite an invalid `DBUS_SESSION_BUS_ADDRESS` and restarted
  Ardour; PipeWire itself remained the failed generation-177 process. Ardour's
  readiness helper is consequently waiting on unresponsive `pw-link` probes.
  Do not interpret this mixed live state as a test of the new package. Stage
  the reused system output and reboot for qualification.
- NixOS generation 178 is staged and is the systemd-boot default. Both the
  system profile and boot entry point to the verified `rzczcz03...` system
  output. A clean reboot is the remaining deployment boundary.
- Generation 178 reproduced generation 174 under the corrected priorities.
  Ardour startup caused one `FFADO:1 PipeWire:1` recovery, followed by 264
  reconstructed-CTR discrepancies. Both ISO handlers survived and the source
  driver continued at 48 kHz/128 frames, but downstream error counters rose on
  every graph cycle. A direct 10-second, 16-channel recording again completed
  in real time with exactly 480,000 frames and every sample was zero. This
  disproves realtime priority inversion as the cause of generation 174's
  failure and rejects normal callback processing as a recovery fix.
- **Decision:** stop changing recovery semantics without observing the callback
  order. Keep normal callback behavior and add a one-shot, 32-event trace armed
  by the first `SPA_IO_CLOCK_FLAG_XRUN_RECOVER` callback. Record only callback
  identity, recovery flag, `done`, `triggered`, and the capture/playback
  transfer flags. This bounded diagnostic deliberately avoids permanent RT log
  spam and changes no audio state.
- The bounded trace patch dry-applies to the exact post-`ffado-driver.patch`
  source without fuzz. The complete system built successfully as
  `/nix/store/wcn1axp0vk2n5ynyhccfc90dzy55zm5h-nixos-system-deepthought-26.05.20260809.fcb8fcd`,
  and the matching Home Manager generation built and activated as
  `/nix/store/yrf6k44pp3a001rm2pk32g4lihwqwzgh-home-manager-generation`.
  Activation restarted Ardour but did not restart the failed generation-178
  PipeWire process. Stage the system output and reboot to collect the trace.
- NixOS generation 179 is staged as the system profile and systemd-boot
  default; its boot entry points to the verified `wcn1axp...` trace build.
  Reboot is the remaining deployment boundary.
- Generation 179 captured the first recovery sequence. The source callback
  entered with `recover:1 done:0 triggered:0 capture:1 playback:0`, then took
  its synthetic path and supplied playback silence. Every subsequent hardware
  wakeup ran one normal source callback (`triggered:1`, capture transferred),
  followed by another recovery source callback because playback was still not
  transferred. No sink callback appeared anywhere in the 32-event trace. This
  proves the recovery loop is caused by the duplex playback node never being
  evaluated, not by FFADO capture transfer or recovery timing.
- PipeWire's working JACK duplex tunnel establishes the intended topology: its
  sink has the higher driver priority and duplex hardware wakeups trigger that
  sink; the source is then evaluated as a graph follower. FFADO currently gives
  the source higher priority and explicitly triggers it first. **Decision:**
  mirror the JACK tunnel: make the FFADO sink the higher-priority driver and
  trigger it whenever sink mode is present, falling back to source only in
  source-only mode. Remove the temporary trace, retain the normal recovery
  callback behavior for qualification, and keep 48 kHz/128/3 unchanged.
- The resulting two-line scheduling fix and priority reversal apply cleanly to
  the exact PipeWire 1.6.8 source. The post-patch source confirms duplex selects
  `impl->sink.filter`, pure source selects `impl->source.filter`, and sink/source
  default priorities are 35001/35000. The local Saffire overrides likewise use
  4001/4000.
- The sink-driven build completed successfully as
  `/nix/store/paf6z5jjf1xm4g7iql0hxy2a0lwzzvny-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  Its matching Home Manager generation is
  `/nix/store/63zysigrpya5b88lh2370m27snkbamj4-home-manager-generation`
  and is active. The activation reached its Ardour service reload, but the
  readiness helper could not query the already-failed generation-179 PipeWire
  graph. The pending Ardour start was stopped so activation could finish; this
  is expected to recover normally after booting the new PipeWire build.
- NixOS generation 180 is staged as both the system profile and systemd-boot
  default. Its boot entry points to the verified `paf6z5...` system output.
- Generation 180 booted with the sink as graph driver and the source correctly
  assigned as its follower. Capture no longer remained zero: a minimal direct
  duplex test wrote exactly 480,000 16-channel frames in 10.1 seconds, with
  real microphone data on channel 1 (peak 0.0227). However, FFADO's playback
  event buffer was continuously overrun. The graph trace showed the sink
  driver completing while another sink endpoint remained pending.
- Comparison with the JACK duplex callback found the remaining scheduling
  error. A triggered sink driver is invoked once to start the graph and again
  after its upstream nodes have produced playback. JACK returns from the first
  invocation for every mode containing `MODE_SINK`; FFADO only returned in
  sink-only mode. Sink-driven duplex therefore transferred playback twice per
  hardware period. **Decision:** change the existing guard from
  `impl->mode == MODE_SINK` to `impl->mode & MODE_SINK`. This is the only new
  behavior change; retain sink-first triggering, priorities, 48 kHz/128/3,
  and normal recovery callback processing. The complete patch dry-applies to
  the exact PipeWire 1.6.8 source.
- The corrected system built successfully as
  `/nix/store/2vf1w8prqnm8bkigbpmlv6d0krb2snkm-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  Its matching Home Manager generation is
  `/nix/store/599f4l1inmbzn64y0h0ic5alqa67dfzr-home-manager-generation`
  and is active. Activation started Ardour as configured; it was stopped again
  immediately so the old live PipeWire/FFADO process cannot affect the reboot
  qualification.
- NixOS generation 181 is staged as both the system profile and systemd-boot
  default. Its boot entry points to the verified `2vf1w8...` output.
- Generation 181 booted the intended sink-driven topology, but Ardour startup
  produced three FFADO xruns, then a capture event-buffer overrun storm and an
  unrecoverable receive-stream restart failure. The graph stopped advancing.
  This disproved the sink guard as a complete fix but exposed its symmetric
  source-side bug: after the triggered sink clears `impl->rt.triggered`, the
  duplex source callback enters FFADO's unconditional `!triggered` completion
  branch and never transfers capture. The working JACK tunnel restricts that
  branch to `MODE_SOURCE`. **Decision:** make the same one-line qualification
  in FFADO. Together, the two callback guards now exactly mirror JACK's duplex
  scheduling: first sink pass starts the graph, duplex source transfers
  capture, and the final sink pass transfers playback. Both patches apply to
  PipeWire 1.6.8, and the post-patch source confirms this callback sequence.
- The paired-guard system built successfully as
  `/nix/store/zd5cz772fmlkjmq5g7nynswah04jy26g-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
  Its matching Home Manager generation is
  `/nix/store/02my3kl101fbj55ivg53wlw1j2axi88g-home-manager-generation`
  and is active. Activation restarted Ardour as configured; Ardour was stopped
  immediately because generation 181's FFADO transport is already failed.
- NixOS generation 182 is staged as both the system profile and systemd-boot
  default. Its boot entry was verified to reference the exact `zd5cz7...`
  system output above.
- Generation 182 booted successfully into the exact staged output. The FFADO
  sink is the active 48 kHz/128-frame graph driver and the duplex source follows
  it via `node.driver-id`; both remain running. The intended FIFO priorities are
  live (FireWire IRQ 99, transmit 94, ARM 93, receive 92, PipeWire graph 88).
  Ardour recovered with its microphone, application-strip-to-master, and
  master-to-Saffire links intact. Startup logged one recovered FFADO/PipeWire
  xrun and a bounded burst of one-cycle CTR discrepancies, but no event-buffer
  overrun storm, fatal FFADO error, or transport failure.
- A direct 16-channel capture from `saffire_ffado_input` completed exactly
  480,000 frames (10.000 seconds) while duplex playback remained active.
  Physical microphone channel 1 measured peak 0.067795 and RMS 0.011371;
  other analog channels contained only their noise floor and unused channels
  were zero. The graph remained at 48 kHz/128 frames afterward with no new
  FFADO journal errors or physical-driver error count.
- Physical duplex through Ardour passed: Firefox played correctly in both
  headphone channels while the microphone and Ardour master meters remained
  live. Five Firefox video switches/reloads also preserved playback, capture,
  and master routing. Post-transition inspection showed both FFADO nodes still
  running, the physical driver at zero errors, and no new FFADO journal entry.
  Ardour recorded several recoverable graph xruns during stream transitions;
  none wedged or interrupted the FFADO transport.
- Ten minutes of continuous Firefox playback completed without an audible,
  microphone, or Ardour-master interruption. The final snapshot retained the
  48 kHz/128-frame FFADO sink driver with zero errors, its running capture
  follower, every required Ardour route, and the intended realtime priorities.
  The FFADO journal remained clean throughout sustained playback. **Decision:**
  generation 182 passed the no-wedge qualification for the Saffire at 48
  kHz/128 frames/3 periods.
- Extended listening exposed frequent audible xruns despite the transport
  remaining live. **Decision:** reject 128/3 for production audio quality and
  return to 48 kHz/256 frames/2 periods. Retain the paired duplex scheduling
  fix and realtime priority hierarchy; quantum/period count and Ardour's
  requested PipeWire latency are the only configuration changes.
- The 256/2 Home Manager configuration built successfully as
  `/nix/store/npavipjyiqq52q1n86a90y2m7nhsjapf-home-manager-generation`.
  The NixOS build remains the already-staged generation-182 output
  `/nix/store/zd5cz772fmlkjmq5g7nynswah04jy26g-nixos-system-deepthought-26.05.20260809.fcb8fcd`
  because the quantum, FFADO period count, and Ardour latency are all managed
  in the user configuration; the patched PipeWire package and system priority
  configuration did not change.
- Home Manager generation `npavip...` is active. Its installed PipeWire fragment
  was verified at 48 kHz/256/2 and the running Ardour unit now exports
  `PIPEWIRE_LATENCY=256/48000`. The live FFADO process intentionally remains at
  128/3 until reboot. The system profile, systemd-boot default, and generation
  182 boot entry all still reference the verified `zd5cz7...` system output.
- The mixed live state subsequently failed and must not be treated as a 256/2
  test. Home Manager restarted Ardour at 14:08 with its new 256-frame request
  while the existing FFADO graph remained fixed at 128/3. That immediately
  caused two playback-ringbuffer overflows (`544, 511`) and FFADO xruns. About
  four minutes later the receive and transmit ISO handlers timed out and died;
  FFADO recovery ended in `Could not syncStartAll`, `Unhandled XRUN`, and a
  zero-rate graph. **Decision:** do not attempt a live teardown/reopen. Preserve
  this failure evidence and reboot when convenient so PipeWire and every client
  start together at 256/2.
- The subsequent clean reboot started the verified generation-182 system and
  active Home Manager files at 48 kHz/256 frames/2 periods; Ardour also requests
  `256/48000`. The sink is the graph driver with zero errors, the duplex source
  follows it, all required Ardour routes are intact, and the intended realtime
  priorities remain live. Ardour startup caused one playback-ringbuffer
  overflow and one recovered FFADO/PipeWire xrun, followed by bounded CTR
  warning bursts. No relevant warning appeared after 14:41:53 and the graph
  continued advancing normally. This matches the accepted single-startup-xrun
  behavior; physical duplex qualification remains.
- Physical 256/2 duplex passed: Firefox playback was correct, microphone and
  Ardour master paths were live, and no audible fault was reported during the
  initial listening period. The post-test snapshot retained a zero-error FFADO
  driver, zero Ardour xruns since startup, all required routes, and no FFADO
  journal warning after the bounded startup burst. **Decision:** accept 256/2
  for normal use and use that normal workload as the remaining soak test.
- Official PipeWire `master` was fetched at
  `30ff8da174121567c06a576bf2a83e71779ee991` (reported version 1.7.0). This is
  the base of the tested FFADO work. Submission branch
  `fix/ffado-duplex-master` squashes the hardware-proven duplex scheduling,
  paired process guards, normal recovery callback processing, priority order,
  and lifecycle correction into signed commit `3a2ae07d6`. Its diff changes
  only `src/modules/module-ffado-driver.c`.
- A native Meson build explicitly enabled libffado and tests. The complete
  1,161-target tree compiled, including
  `libpipewire-module-ffado-driver.so`, and all 53 enabled tests passed. The
  isolated build linked against the development environment's libffado 2.4.9;
  this establishes source and test compatibility but is not the intended
  runtime package.
- The reproducible Nix override pins the same master commit, applies
  `ffado-master.patch`, retains libffado 2.5.0, omits the obsolete downstream
  `musl.patch` already incorporated upstream, and disables only the unavailable
  optional LHDC codec. The Nix package built successfully and reports PipeWire
  1.7.0 linked to libffado 2.5.0. The older 1.6.8 patch files remain in the
  repository but are unused by this master test, preserving the rollback
  record.
- The complete master-test system built as
  `/nix/store/rj0ff1yp0zypxz3fm8isnny1bismxh9z-nixos-system-deepthought-26.05.20260809.fcb8fcd`
  and Home Manager as
  `/nix/store/w13wnv7kyv57757qa98cjjb48yql7md1-home-manager-generation`.
  The system PipeWire unit explicitly launches the pinned 1.7.0 package, the
  Ardour wrapper uses its matching 1.7.0 JACK library, and the generated FFADO
  configuration remains 48 kHz/256/2. Neither closure has been staged or
  activated, so the working 1.6.8 audio process is unchanged.
- The master-test NixOS output is staged as generation 183. The system profile,
  systemd-boot default, and generation-183 boot entry all point to the verified
  `rj0ff1...` output. The matching Home Manager output is deliberately not yet
  active; activate it only immediately before reboot to avoid an extended
  mixed 1.6.8-server/1.7.0-client session.
- The matching Home Manager generation `w13wnv...` is now active. Activation
  briefly restarted Ardour, which was immediately stopped; the unit is inactive
  and no Ardour process remains. Its wrapper selects the matching PipeWire
  1.7.0 JACK library and retains `PIPEWIRE_LATENCY=256/48000`. Generation 183
  remains the verified system profile and boot default. Reboot is now the only
  remaining deployment boundary; do not restart Ardour against the old live
  PipeWire server.

### 2026-08-13 — First PipeWire-master hardware failure and lifecycle correction

- Generation 183 booted the pinned PipeWire 1.7.0 master candidate with the
  matching Home Manager/JACK closure. Ardour's saved links were present, but
  microphone capture did not move and `pw-top` showed a zero-rate graph.
- The journal showed two FFADO initializations: one with PipeWire startup and
  another when Ardour activated the filters. The recreated DICE stream warned
  that its ARX ISO channel was still assigned, then produced full playback
  ringbuffers, a recovered-xrun burst, dead receive and transmit handlers,
  `Could not syncStartAll`, `Unhandled XRUN`, and a permanently stopped graph.
  This establishes a transport lifecycle failure rather than missing routing.
- Comparing the effective master driver to the hardware-proven 1.6.8 driver
  isolated the relevant difference: the master fix series closed the FFADO
  device when both filters entered PAUSED, whereas 1.6.8 only stopped
  streaming and retained the open device. Submission commit `3a2ae07d6`
  restores the proven behavior without reintroducing recursive close
  ownership.
- `ffado-master.patch` is the exact diff of submission commit `3a2ae07d6`
  against upstream master. All 53 enabled upstream tests pass after the
  correction. A
  fresh Nix build compiles the corrected FFADO module as PipeWire 1.7.0 against
  libffado 2.5.0. The complete corrected outputs are
  `/nix/store/zms36g9dmpj4mcpq6whjdcgigc166750-nixos-system-deepthought-26.05.20260809.fcb8fcd`
  and
  `/nix/store/69jrb9g4f5b4prcr37w9b2x4invvydzi-home-manager-generation`.
  Do not try to recover the currently dead graph in place.
- The corrected system is staged as generation 184 and is the systemd-boot
  default. Its matching Home Manager generation is active, the Ardour service
  requests `256/48000` through the matching PipeWire 1.7.0 JACK library, and
  Ardour is stopped. Reboot is the next deployment boundary.
- Generation 184 booted consistently. PipeWire 1.7.0 drives the Saffire at
  48 kHz/256, the duplex source follows it, every microphone, strip-to-master,
  and master-to-Saffire link is active, and physical microphone and playback
  initially work normally. One accepted startup xrun occurred at 16:07:29;
  no subsequent FFADO warning or transport failure appeared during the initial
  check.
- Extended generation-184 use exposed a separate fatal-wait recovery defect.
  The graph recovered isolated FFADO xruns at 17:39:19 and 17:52:55, then an
  xrun at 18:47:47 left the receive handler without activity. FFADO's
  two-second watchdog reported the receive handler dead at 18:48:34 and the
  transmit handler dead at 18:48:36. Its internal restart failed with
  `Enable requested on enabled stream 'Receive'`, `Could not syncStartAll`,
  and `Unhandled XRUN` at 18:48:39. There was no kernel bus reset or FireWire
  controller error, and the Saffire remained enumerated on `07:00.0`.
- PipeWire's FFADO timeout callback handles `ffado_wait_error` only by logging
  `FFADO error` and returning. It leaves both nodes and every client in
  `running` state while the driver clock remains permanently at zero; 8,591
  ISO inactivity warnings accumulated before the failure was inspected. This
  is not the first master candidate's PAUSED close/reopen failure and does not
  invalidate that lifecycle correction. It is a missing fatal-transport reset
  path that must be addressed separately before the upstream patch can claim
  long-term no-wedge behavior.
- A normal full-stack stop could not terminate the dead FFADO process. After
  stopping its socket-activated services, killing that PipeWire process, and
  starting a fresh stack, the same boot recovered without a FireWire reset or
  reboot. PipeWire returned to 48 kHz/256/2, Ardour restored all expected
  routes, and physical microphone and Firefox playback both work again. This
  is a recovery procedure, not a fix for the fatal-wait defect.
- On 2026-08-14, after about 15.5 hours of operation, the same failure recurred.
  The receive handler exceeded FFADO's two-second activity threshold at
  12:56:24, the transmit handler died two seconds later, and `syncStartAll`
  again failed because the receive stream was already enabled. The graph clock
  fell to zero with no kernel bus reset or controller error.
- This occurrence did not permit the earlier process-only recovery. `SIGKILL`
  left an FFADO bus-reset thread uninterruptibly blocked in
  `fw_device_op_release`. Physically cycling the bus-powered Saffire, a
  controller-local bus-reset attempt, and a PCI function reset did not release
  it. Hot-removing the dedicated `05:03.0` PCIe branch did release the process.
  After rescanning, a fresh PipeWire process initialized FFADO threads but
  never published a usable graph or completed client connections; stopping it
  produced the same kernel wait through the FFADO watchdog thread. A second
  hot-remove released that process. Do not repeat hot rescan/start recovery in
  this boot; reboot with the controller absent as the clean recovery boundary.
- The subsequent reboot restored controller `07:00.0`, the Saffire GUID, and
  the complete graph. Ardour started normally with the saved capture,
  strip-to-master, and master-to-Saffire routes. Physical playback was
  confirmed at 48 kHz/256/2. Recoverable CTR-discrepancy/xrun bursts occurred
  at 13:31, 14:36, and 14:57 without stopping the graph; no new handler death,
  fatal wait error, or `syncStartAll` failure followed them.

### 2026-08-14 — Fatal-transport instrumentation

- Created local PipeWire branch `diagnostic/ffado-fatal-trace` from
  `fix/ffado-duplex-master` without changing or pushing the merge-request
  branch. Its uncommitted diagnostic change is confined to
  `src/modules/module-ffado-driver.c`.
- The module now retains 4,096 wait, source/sink callback, and
  capture/playback events in memory. At 48 kHz/256 this covers approximately
  the final 3.6 seconds, including FFADO's two-second no-activity interval.
  Each record contains monotonic time, callback order and clock flags, FFADO
  response or transfer result, frame time, `done`, `triggered`,
  capture/playback completion, node-running state, and device-started state.
  The RT path performs only fixed-size memory writes. Nothing is logged until
  the first fatal wait, when the ring is dumped once as `FFADO_TRACE` lines.
- Added Home Manager user service `ffado-failure-monitor.service`. It finds
  the Saffire's current controller IRQ from GUID `0x00130e0401c04de0`, then
  samples the aggregate IRQ count and `schedstat` for `data-loop.0`,
  `FW_ISOXMT`, and `FW_ISORCV` every 250 ms. It rotates after 4,096 samples
  in `$XDG_RUNTIME_DIR/ffado-failure-monitor`. When PipeWire logs
  `FFADO error`, it saves the final 20 seconds of samples and journal context
  under
  `$XDG_STATE_HOME/ffado-diagnostics/ffado-failure-<UTC timestamp>.log`.
- The local `pipewire-src` lock was refreshed to diagnostic source hash
  `sha256-oZLgKnyYe5+HBCtZBZ3QhWGIF4CE5tHYA4LfFw1KkVM=`. Nix compiled the
  instrumented module successfully as
  `/nix/store/6awj0w7a853qs0ggyy09vy785cpgvbrj-pipewire-1.7.0-unstable-2026-08-06`.
  The binary contains both the bounded-trace header and event format.
- The Home Manager output built successfully as
  `/nix/store/i48q2l6n2sjhhj5cfnvpkrrafsa0wxgq-home-manager-generation`.
  The complete NixOS output built successfully as
  `/nix/store/94dyll5csjmkvagfcs3lil18dliq3m8a-nixos-system-deepthought-26.05.20260809.fcb8fcd`.
- A non-activating two-second watchdog smoke test found the live Saffire on IRQ
  39 and correctly sampled PipeWire PID 2238 plus all three target realtime
  threads. IRQ totals and every thread's runtime/switch counters advanced
  between samples. The test process and sampler child exited cleanly, and
  `wpctl status` still reported the live Saffire graph and Firefox-to-Ardour
  stream. Neither the new PipeWire binary nor the persistent service is active
  yet.
- `nixos-rebuild switch` activated the verified system without a reboot and
  restarted PipeWire as PID 260774 from the final diagnostic package. Home
  Manager generation `i48q2l6...` is active and
  `ffado-failure-monitor.service` is sampling IRQ 39 plus all three intended
  realtime threads.
- The live graph runs at 48 kHz/256 with zero Saffire driver errors. All saved
  links are restored: Saffire capture to the Ardour Mic strip, Firefox to its
  Ardour strip, every program strip to Master, and both Master outputs to the
  Saffire. Two FFADO/PipeWire xruns accompanied stack and Ardour startup; both
  recovered, and there is no handler death, fatal wait, `syncStartAll`
  failure, or fatal trace dump.
- Physical post-activation duplex qualification passed: Firefox playback
  reaches the Saffire normally and the microphone is active in Ardour.
  **Decision:** leave the diagnostic 256/2 stack running under normal workload
  until the long-duration failure recurs or the soak period is sufficient.
- The instrumented stack reproduced the fatal failure at 17:49 after
  approximately two hours of normal use. The monitor automatically saved
  `~/.local/state/ffado-diagnostics/ffado-failure-20260814T164951Z.log`;
  a second copy of its live ring was preserved under
  `/tmp/ffado-hang.TRde2E` before rotation.
- The 4,096-event module trace contains 682 normal hardware waits and 683
  complete duplex periods. Every period followed the intended sink trigger,
  playback, source, and capture order; every transfer succeeded. There was no
  callback omission, transfer failure, or PipeWire-side xrun in the retained
  interval. The only pre-failure timing anomaly was a 14.2 ms wait gap during
  the final reconstructed-CTR burst. The next wait remained inside libffado
  for 10.43 seconds and returned `ffado_wait_error`.
- The host trace isolates the initiating boundary below PipeWire scheduling.
  IRQ 39 advanced normally through monotonic 16356.60, then stopped permanently
  at 12,366,499 during the CTR-discrepancy burst. PipeWire's data loop and both
  FFADO ISO threads were scheduled normally before that point; the data loop
  continued executing libffado's failed recovery after IRQ activity ceased.
  FFADO declared both handlers dead approximately two seconds later, then
  failed `syncStartAll` because its transmit processor could not enter dry
  running. No kernel FireWire, PCIe, AER, bus-reset, or IRQ error was logged.
  The controller remained enumerated, runtime-active, forced to power
  `control=on`, and linked at PCIe 2.5 GT/s x1.
- **Finding:** no PipeWire callback or transfer anomaly immediately preceded
  this occurrence. The first directly observed failure is cessation of all
  Saffire-controller interrupt activity during FFADO receive timestamp
  reconstruction. This does not exclude a longer-term interaction between
  PipeWire's transfer cadence and libffado state. The evidence also does not
  yet distinguish the Saffire ceasing isochronous transmission from the OHCI
  controller ceasing to deliver it. Instrumenting libffado packet reception or
  comparing the same controller and device under JACK/FFADO is the next
  diagnostic boundary.
- A coordinated post-capture stop reached the known FFADO teardown failure:
  `StreamProcessorManager::stop` timed out waiting for its stream processors.
  PipeWire remained in systemd `stop-sigterm` pending the normal 90-second
  service timeout; no manual kill or PCIe manipulation was used.
- At the 90-second timeout, systemd sent `SIGKILL`. The PipeWire leader became
  a zombie, but `FW_ARMSTD` survived in uninterruptible `D` state at
  `fw_device_op_release`. The service is consequently stuck in
  `final-sigterm` and cannot be restarted normally. This exactly reproduces
  the kernel teardown boundary from the prior occurrence. A reboot is the
  preferred recovery; hot-removing the upstream PCIe branch is rejected unless
  explicitly requested because its previous rescan did not restore a usable
  controller.
- Reboot cleared the blocked `FW_ARMSTD` thread without PCIe manipulation.
  The final diagnostic NixOS generation returned with PipeWire PID 2242,
  `ffado-failure-monitor.service`, WirePlumber, Pulse, and Ardour active. IRQ
  39 and all three monitored realtime-thread counters advance normally. The
  Saffire drives the graph at 48 kHz/256 with zero driver errors, and all saved
  capture, strip-to-master, and master-to-Saffire routes are restored. One
  accepted startup xrun occurred; no fatal FFADO event followed it.
- The same instrumented process failed again at 20:28, approximately 2 hours
  17 minutes after boot. The monitor saved
  `~/.local/state/ffado-diagnostics/ffado-failure-20260814T192815Z.log`. IRQ 39
  stopped at 6,257,673 during another reconstructed-CTR burst, followed by the
  same 10.26-second blocked wait, dead ISO handlers, failed `syncStartAll`, and
  `ffado_wait_error`. The retained PipeWire trace again shows complete,
  successful duplex callback cycles immediately before the blocked wait.
- **Decision:** pause the FFADO investigation and return production audio to
  the previously working PipeWire/ALSA Saffire path. The flake-level
  `useSaffireFfado` switch is `false`; it selects stock PipeWire, allows
  `snd_dice`, restores ALSA node readiness/routing, and omits the FFADO module
  and failure monitor. Keep the FFADO configuration, diagnostic source branch,
  lock entry, and both failure snapshots for the next investigation session.
- The ALSA Home Manager generation is active: the FFADO module link and failure
  monitor are absent, the Ardour readiness check targets the Saffire ALSA
  nodes, and its JACK wrapper uses stock PipeWire. NixOS generation 186 is the
  boot default and its system profile selects stock PipeWire while omitting
  `snd_dice` from the kernel-module blacklist. Reboot is the remaining recovery
  step because the failed live FFADO process must not be torn down in place.
- Rebooted successfully into generation 186. `snd_dice` owns the Saffire and
  publishes its 8-channel playback and 16-channel capture devices through stock
  PipeWire 1.6.6. Ardour passed the ALSA readiness check; Firefox-to-Ardour,
  every strip-to-master, master-to-Saffire, and Saffire-to-input route is
  active. The graph runs at 48 kHz/1024 with zero errors. Physical Firefox
  playback through the Saffire and microphone input in Ardour both passed.

## Current state and remaining work

The AudioFire remains physically disconnected. FFADO is paused after two
instrumented failures showed the controller IRQ stopping during FFADO receive
timestamp reconstruction. PipeWire/ALSA is active for the Saffire on generation
186 and passes the technical graph, routing, playback, and microphone checks.
The upstream branch remains at `81eeba1f6`; do not push the temporary
instrumentation.

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
