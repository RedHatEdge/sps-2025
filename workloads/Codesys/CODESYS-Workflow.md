# CODESYS workflow — Marketing Demo Stand

This doc focuses on **Purdue Model Level 0 (physical process) and Level 1 (basic control)** for the marketing demo stand: the field devices themselves, the CODESYS logic that controls them, and how a logic change gets deployed to the vPLC running on IPC2. It does not cover the platform/GitOps layers (IPC4 build, Gitea, ArgoCD, SNO) — see [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md) for that.

## 1) What's in this folder

- **`RedHat_Demo_MarketingStand_Working.xml`** — a plain-text CODESYS project export (`Project → Export`). This is the git-friendly artifact: diffable, reviewable, small enough to track normally. It contains the full device tree, task configuration, POUs, and global variables, but not compiled binaries or referenced libraries.
- **`09_19_426pmRedHat_Demo_MarketingStand_Working.projectarchive`** — the full CODESYS project archive (`.projectarchive`), including referenced libraries and everything needed to reopen and rebuild the project as-is in the IDE. Large binary file — tracked via **Git LFS** (see the main [README.md](../../README.md#codesys-ide-win11-on-ocp-v), step 12).

Treat the `.xml` as the reviewable record of what the logic does; treat the `.projectarchive` as the thing you actually open in CODESYS IDE to keep working on it.

## 2) Level 0 — the physical process

Level 0 of the Purdue Model is the physical process itself: the sensors and actuators that do the actual work, with no logic of their own. On this demo stand that's pushbuttons, indicator LEDs, toggle switches, a potentiometer, a three-color stack light, a relay, and a small motor — wired to three EtherNet/IP field devices on the `192.168.100.0/24` network:

| Device | Role | Address | I/O it exposes |
|---|---|---|---|
| `Opto22_RIO1` — [groov RIO](https://www.opto22.com/products/groov-rio) | Universal edge I/O | `192.168.100.11` | `Red_Button`, `Green_Button`, `Blue_Button` (digital in) → `Red_Button_LED`, `Green_Button_LED`, `Blue_Button_LED` (digital out); `Relay_In`, `Relay_Out` |
| `Opto22_RIO2` — [groov RIO](https://www.opto22.com/products/groov-rio) | Universal edge I/O | `192.168.100.12` | `Toggle_1`, `Toggle_2` (digital in), `Potentiometer` (analog in) → `Red_Stacklight`, `Yellow_Stacklight`, `Green_Stacklight` (digital out) |
| `TSM23XIP_XD` — Applied Motion [TSM23 integrated step-servo](https://www.applied-motion.com/products/series/ethernet-ip-products) | Motion / actuation | `192.168.100.13` | Demo motor motion commands + status, over CIP explicit and implicit (I/O) messaging |

**groov RIO** (Opto 22): a rack-free, PoE-powered edge I/O module. Each unit here provides 8 software-configurable channels (any mix of digital/analog in or out) plus 2 electromechanical relays, an onboard I/O processor, and — beyond the EtherNet/IP CIP adapter mode used by this project — native support for MQTT/Sparkplug, OPC UA, Modbus/TCP and REST, none of which this demo currently uses. Reference: [ETH-IP-IO-Module](../ETH-IP-IO-Module/) in this repo (`groovFind.exe` for discovery, the groov RIO user's guide), and Opto 22's own [groov RIO data sheet](https://documents.opto22.com/2317_groov_RIO_Data_Sheet.pdf).

**TSM23XIP-XD** (Applied Motion Products): a NEMA 23 integrated closed-loop step-servo — motor, drive electronics, and an EtherNet/IP interface combined into one unit, powered at 24–48VDC. It exposes over 100 commands and 130 registers over EtherNet/IP for motion control, I/O, and configuration. Reference: [ETH-IP-StepServoDrive](../ETH-IP-StepServoDrive/) in this repo (hardware manual, EDS file, step-servo tuner utility), and Applied Motion's [EtherNet/IP product line](https://www.applied-motion.com/products/series/ethernet-ip-products).

All three are **EtherNet/IP CIP adapters** (targets): they accept the Class 1 (implicit, cyclic I/O) connection from a scanner and expose input/output assemblies, and also answer Class 3 (explicit) service requests. They never initiate traffic themselves — that's the scanner's job, which is where Level 1 comes in.

## 3) Level 1 — basic control (the vPLC)

Level 1 is the controller that closes the loop on Level 0: it scans inputs, runs logic, and drives outputs. Here that's a **CODESYS soft-PLC runtime (vPLC) running as a Podman container on IPC2** (hostname `control2-rt.sps2025`, a bootc image built from `quay.io/luferrar/sps:ipc-rh10-rt` — RHEL10 with a realtime kernel; see `images/ipc2/ContainerfileCodesys`). The runtime is [CODESYS Virtual Control SL](https://www.codesys.com/products/runtime/virtual-control-sl/), CODESYS's runtime built specifically to run under a container or hypervisor rather than bare metal. §4 covers how it's deployed manually today; §5 covers the target build/push/deploy workflow for shipping application changes as a new container image.

IPC2 has **two network roles** split across separate interfaces:

- **`eno1`, `192.168.100.225/24`** — dedicated to the vPLC container for EtherNet/IP CIP traffic, mapped in via the instance's `Nic` setting. This is on the same `192.168.100.0/24` segment as `Opto22_RIO1`, `Opto22_RIO2`, and `TSM23XIP_XD`.
- **`192.168.100.227`** — IPC2's management address, used for the CODESYS Gateway connection from the IDE (port `11740`, opened through the firewall for remote management) and for CodeMeter license-server discovery.

The container also exposes `4840` (OPC UA server) and `8080` (WebVisu/HTTP) alongside `11740`. Licensing runs through CodeMeter (WIBU-SYSTEMS) — the container's instance config points its `License Server` setting at `192.168.100.223`; the host itself also runs `codemeter.service` (installed via `images/ipc2/CodeMeter-lite-8.40.7131-502.x86_64.rpm`, see `images/ipc2/ContainerfileCodesys`).

Inside the `Device` → `Application`, the project structure is:

- **`PLC_PRG`** — the main program, cyclically scheduled by **`MainTask`**. It reads the Level 0 inputs (buttons, toggles, potentiometer), runs the demo logic, and writes the Level 0 outputs (LEDs, stack lights, motor commands).
- **`FUNC_SCALE`** — scales the raw `Potentiometer` analog reading into an engineering-range value used elsewhere in the logic.
- **`LIGHT_CYCLE`** — drives the red/yellow/green stack-light sequencing.
- **`MOTOR`** — issues motion commands to the `TSM23XIP_XD` servo drive.
- **`GVL`** — the global variable list binding these POUs to the actual I/O channel names shown in the table above.

The EtherNet/IP side of Level 1 is handled by the `Ethernet` → `EtherNet_IP_Scanner` device, which acts as the CIP **scanner** (connection originator) for all three Level 0 adapters, and by two dedicated tasks:

- **`ENIPScannerIOTask`** — the cyclic Class 1 I/O scan: pulls current input assemblies from `Opto22_RIO1`/`Opto22_RIO2`/`TSM23XIP_XD` and pushes current output assemblies to them, on every scan.
- **`ENIPScannerServiceTask`** — Class 3 explicit/service messaging (e.g. one-off parameter reads/writes, diagnostics) to the same three devices.

This is what actually reaches the field devices over `eno1`, as described above.

## 4) Manual deployment of the Codesys Application to softPLC

Deploy Control SL (softPLC) to the Device (this will download the softPLC container image to the Device)
![alt text](image-3.png)

Connect to the new Device (via SSH)
![alt text](image-4.png)

Install Virtual Control to the Device (import image to Podman)
![alt text](image-5.png) 

Installed!
![alt text](image-6.png)
```bash
[admin@control2-rt ~]$ sudo podman images
REPOSITORY                                     TAG                  IMAGE ID      CREATED       SIZE
quay.io/luferrar/sps                           ipc-rh10-rt-codesys  aa41f53b572c  11 hours ago  3.84 GB
quay.io/luferrar/sps                           ipc-rh10-rt          f85ac7a8d20f  16 hours ago  3.65 GB
docker.io/library/codesyscontrol_virtuallinux  4.21.0.0             a6590499224a  8 weeks ago   152 MB
```

Add a new instance of Virtual Control (configuration of a container)
![alt text](image-7.png)

New VPLC container
![alt text](image-8.png)

Configure exposed / mapped ports
![alt text](image-21.png)
>Notice how License server address is configured (if you have a valid license there) and Network section is filled in with an interface information (in this case eno1 has to be dedicated since we are using Eth/IP as protocol)  
> **REFERENCE** for configuration [here](https://content.helpme-codesys.com/en/CODESYS%20Control/_rtsl_reference.html) 

Start the instance
![alt text](image-9.png)

Opening target Device properties
![alt text](image.png)  

Adding new Device (IPC2)  
*Use the other available interface to connect to the IPC*
![alt text](image-1.png)

Have to open firewall port 11740 for remote management
![alt text](image-2.png)

Connected!
![alt text](image-11.png)

Before uploading the application, make sure the IP addresses for Ethernet/IP components are correct
![alt text](image-10.png)  
![alt text](image-15.png)  
![alt text](image-17.png)  
![alt text](image-18.png)

Deploy the application to VPLC
![alt text](image-12.png)

User management for VPLC (using password `R3dh4t123!`)
![alt text](image-13.png)

Upload the application to VPLC
![alt text](image-14.png)

Start the application on VPLC
![alt text](image-16.png)

![lab-recording](output.gif)

Codemeter Licensing
![alt text](image-19.png)

## 5) Target workflow: build → push → deploy (not yet implemented)

§4 above is how the application is deployed **today**: manually, through the CODESYS IDE's device wizard, onto a long-lived `vplc` Podman container running the stock `codesyscontrol_virtuallinux` image on IPC2. The intended target workflow instead bakes the application *into* the container image itself, so a logic change ships as a new image rather than an IDE upload:

1. An engineer edits the logic in CODESYS IDE, opening the `.projectarchive` from this folder, and re-exports the project to `RedHat_Demo_MarketingStand_Working.xml` (re-saving the `.projectarchive` too) — both get committed back to this repo, so the demo logic stays version-controlled.
2. A new container image is built on top of `images/ipc2/ContainerfileCodesys` (which already produces `quay.io/luferrar/sps:ipc-rh10-rt-codesys`, RHEL10 + the CodeMeter RPM), adding a layer that embeds the exported project into the CODESYS Virtual Control SL runtime. (This build step itself — how the project gets baked in — is not yet implemented.)
3. The new image is pushed to the registry and deployed to run as the `vplc` **Podman** container on **IPC2** (`control2-rt.sps2025`), replacing the manual "Deploy Control SL" + "Upload the application" steps in §4.
4. On start, the containerized vPLC loads the project, `MainTask`/`PLC_PRG` begins cycling, and the EtherNet/IP scanner opens Class 1 connections to `Opto22_RIO1`, `Opto22_RIO2`, and `TSM23XIP_XD` over the dedicated `eno1`/`192.168.100.225` interface.
5. Level 1 now closes the loop on Level 0 continuously: button/toggle/potentiometer state in, LED/stack-light/servo-motion commands out.

## Diagram (§5 target workflow)

```mermaid
flowchart LR
  subgraph Repo[This repo]
    ARCHIVE[.projectarchive<br/>opened/edited in CODESYS IDE]
    XML[RedHat_Demo_MarketingStand_Working.xml<br/>re-exported on every change]
  end

  subgraph Build[Container build - not yet implemented]
    IMG[New container image:<br/>ipc-rh10-rt-codesys<br/>+ exported project]
  end

  subgraph IPC2[IPC2 - control2-rt.sps2025 - RHEL10 realtime, Podman]
    VPLC[vplc Podman container<br/>MainTask / PLC_PRG<br/>ENIPScannerIOTask / ENIPScannerServiceTask]
  end

  subgraph Field["Level 0 - EtherNet/IP field devices - 192.168.100.0/24"]
    RIO1[Opto22 groov RIO 1<br/>192.168.100.11<br/>buttons, LEDs, relay]
    RIO2[Opto22 groov RIO 2<br/>192.168.100.12<br/>toggles, potentiometer, stack lights]
    SERVO[Applied Motion TSM23XIP-XD<br/>192.168.100.13<br/>step-servo drive]
  end

  subgraph Stand[Physical demo stand]
    BTNS[Pushbuttons + LEDs]
    TOGGLES[Toggles + Potentiometer]
    LIGHTS[Stack light]
    MOTOR[Motor]
  end

  ARCHIVE -- edit --> XML
  XML -- embedded into --> IMG
  IMG -- deployed to --> VPLC

  VPLC -- "EtherNet/IP scanner over eno1<br/>CIP Class 1 + Class 3" --> RIO1
  VPLC -- EtherNet/IP scanner over eno1 --> RIO2
  VPLC -- EtherNet/IP scanner over eno1 --> SERVO

  RIO1 --- BTNS
  RIO2 --- TOGGLES
  RIO2 --- LIGHTS
  SERVO --- MOTOR

  classDef control fill:#e3f2fd,stroke:#1565c0;
  classDef field fill:#fff3e0,stroke:#e65100;
  classDef repo fill:#e8f5e9,stroke:#2e7d32;
  class ARCHIVE,XML,IMG repo;
  class VPLC control;
  class RIO1,RIO2,SERVO,Stand field;
```

## 6) WIP: defect-check workflow (target design)

**Not implemented yet.** This section documents the target design for gating the motion sequence on an MQTT-based defect check, and where it hooks into the logic that already exists. It's a plan to implement in CODESYS IDE, not a description of current behavior.

### Target behavior

0. **On PLC start**, the machine is in **Standby**: `Yellow_Stacklight` and `Green_Button_LED` both blink, nothing else active.
1. User pushes **Green Button** → blinking stops, machine enters **Running**, and the drive moves to the next position.
2. Once the move completes, the vPLC publishes an MQTT message signaling "position reached."
3. The defect-detection app (running elsewhere, subscribed to that message) analyzes the piece and publishes a single result (defective / not defective) to a results topic, then goes idle again.
4. The vPLC reads that result:
   - **No defect** → green stack light on, wait 3 seconds, then move to the next position.
   - **Defect** → red stack light on, red button LED on, and the sequence holds.
5. User pushes **Red Button** to acknowledge the defect → drive moves to the next position.
6. At any point while **Running** (outside of an active defect-ack hold), pushing **Red Button** stops the routine instead. After 5 seconds, the machine returns to **Standby** (step 0) and resumes blinking.

### What already exists (verified from the project's ladder logic)

- `PLC_PRG` already has a working step sequencer (`Seq0`…`Seq60`, `SeqMov1`, `SeqMov2`, `SeqStop`, `SeqErr`) that: checks run permissives, is started by `Cmd_Run`/`Sequence_Run` (wired alongside `Inp_Green_Button.State`), resets faults, enables the motor, performs an incremental move via the `AMPLib_LD` function blocks (`AMP_Relative_Move_0`, `AMP_Motor_Enable_0`, `AMP_Alarm_Reset_0`, `AMP_Normal_Stop_0`, `AMP_Status_Code_0`), waits for move-complete or a stop, then pauses (`Par_IndexPause` / `TON_IndexPauseDelay`) before looping back for the next move.
- So **"push Green → move to next position" is already implemented.** What's missing is making it *stop and wait for an external decision* after the move, instead of looping on a fixed timer.
- `LIGHT_CYCLE` currently just mirrors whichever pushbutton is pressed onto its matching LED/stack light (a demo/test-rig pattern) — it has no concept of defect/ack/standby yet and will need rework, not extension.
- `Inp_Red_Button` is currently wired as the sequence's **Stop** input (`Cmd_Stop`/`Force_Stop`, per the "Wait For Move To Complete, or Stop button Press" rung) — this maps directly onto the new step 6 above, it just needs the 5-second return-to-standby tacked on.
- **No MQTT client exists in the project at all** — the library list has `EtherNetIP Services`, `AMPLib_LD`, OPC UA (server), `OSCAT`, and the Opto 22 library, but nothing for MQTT or generic TCP/sockets. This is the main missing piece.
- **No standby/blink state exists at all** — there's nothing today gating the sequencer behind a Green-Button-to-arm step; it's armed as soon as permissives are satisfied. The blinking itself has an easy building block, though: `OSCAT_BASIC` (already referenced in the project's library list) ships a [`BLINK`](https://content.helpme-codesys.com/en/libs/Util/Current/Signals/BLINK.html) function block for exactly this (on-time/off-time → toggling output) — no need to hand-roll a flip timer pair.

### 1. New top-level state: STANDBY / RUNNING / STOPPING

`DEFECT_CHECK` (below) only covers what happens *during* a run. It needs to sit inside a higher-level machine state that gates the whole sequence behind Green Button and handles the Red-Button-as-stop path:

```iecst
TYPE E_MachineState : (STANDBY, RUNNING, STOPPING);
END_TYPE

VAR
    machineState    : E_MachineState := STANDBY;
    blinkYellow     : OSCAT_BASIC.BLINK;    // already-referenced library, no new dependency
    tonStopRecovery : TON;
END_VAR

CASE machineState OF
    STANDBY:
        blinkYellow(EN := TRUE, TIME_HIGH := T#500MS, TIME_LOW := T#500MS);
        GVL.Out_YellowStack     := blinkYellow.OUT;
        GVL.Out_GreenButtonLED  := blinkYellow.OUT;
        IF Inp_Green_Button.State THEN
            blinkYellow(EN := FALSE);
            GVL.Out_YellowStack    := FALSE;
            GVL.Out_GreenButtonLED := FALSE;
            GVL.Cmd_Run := TRUE;             // arms the existing PLC_PRG sequencer
            machineState := RUNNING;
        END_IF

    RUNNING:
        // Red Button = stop, EXCEPT while DEFECT_CHECK is holding for an ack
        IF Inp_Red_Button.State AND defectCheck.state <> DEFECT_CHECK.AWAIT_ACK THEN
            GVL.Cmd_Run   := FALSE;
            GVL.Cmd_Stop  := TRUE;           // existing Stop path (Cmd_Stop/Force_Stop)
            tonStopRecovery(IN := TRUE, PT := T#5S);
            machineState := STOPPING;
        END_IF

    STOPPING:
        tonStopRecovery(IN := TRUE, PT := T#5S);
        IF tonStopRecovery.Q THEN
            tonStopRecovery(IN := FALSE);
            GVL.Cmd_Stop            := FALSE;
            GVL.Out_GreenStack      := FALSE;
            GVL.Out_RedStack        := FALSE;
            GVL.Out_RedButtonLED    := FALSE;
            machineState := STANDBY;
        END_IF
END_CASE
```

`DEFECT_CHECK` should itself only run its `IDLE → WAITING_RESULT` transition while `machineState = RUNNING` — gate it on that, so a stop mid-cycle can't leave it waiting on a stale MQTT exchange.

### 2. Add an MQTT client library

| | [Janz Tec MQTT library](https://store.codesys.com/en/janz-tec-mqtt-library-for-codesys-sl.html) | [stefandreyer/CODESYS-MQTT](https://github.com/stefandreyer/CODESYS-MQTT) |
|---|---|---|
| Cost | €49, one license per runtime | Free / open source |
| QoS | 0 and 1 | 0, 1, and 2 |
| Requires | `TCP`, `SysSocket`, `CmpErrors` (standard libs) | Its own TCP-based dependencies |
| Support | Vendor-supported, official CODESYS Store listing | Community, no formal support |
| Fit here | CODESYS Control V3.5.8.10+ — matches Virtual Control SL | Same runtime family, less formally validated |

Recommended: **Janz Tec**, for vendor support on something that may get shown to customers. Add via **Tools → Library Repository** (or the CODESYS Store integration), then reference it on the `Application` node alongside `AMPLib_LD`/`EtherNetIP Services`.

### 3. Topics and payload contract

Reuses what `workloads/defect-rec-sim/app.py` already speaks:

- vPLC **publishes** `model/sim` = `"on"` once a move completes and the piece is in position.
- vPLC **subscribes** to `factory1/lineA/results`, payload JSON like `{"defect_type":1,"defective":true,"confidence_score":0.87,...}` — only the `"defective"` boolean is needed; a plain substring search (`FIND(payload, '"defective":true')`, from the already-referenced `Standard` library) is enough, no JSON library required for this.
- **Companion fix needed on the app side**: `app.py`'s `on_message` handler currently republishes `model/sim`/`"on"` to itself at the end of every cycle (`app.py` around line 48), so it free-runs forever regardless of the PLC. That self-republish needs to be removed so one external trigger produces exactly one result.

### 4. New POU: `DEFECT_CHECK` (Structured Text)

Add as a new ST program on the `Application`, called from `PLC_PRG` each scan — MQTT sequencing and string parsing are much more natural in ST than in the existing ladder:

```iecst
TYPE E_DefectCheck : (IDLE, WAITING_RESULT, GREEN_DELAY, AWAIT_ACK);
END_TYPE

VAR
    state           : E_DefectCheck := IDLE;
    mqttClient      : MQTT_CLIENT;      // from the chosen library
    tonGreenDelay   : TON;
    resultPayload   : STRING(255);
    defective       : BOOL;
END_VAR

CASE state OF
    IDLE:
        IF GVL.Sts_PositionReached THEN     // pulse set by PLC_PRG when a move finishes
            mqttClient.Publish('model/sim', 'on');
            state := WAITING_RESULT;
        END_IF

    WAITING_RESULT:
        IF mqttClient.MessageReceived('factory1/lineA/results', resultPayload) THEN
            defective := FIND(resultPayload, '"defective":true') > 0;
            IF defective THEN
                GVL.Out_RedStack := TRUE;
                GVL.Out_RedButtonLED := TRUE;
                state := AWAIT_ACK;
            ELSE
                GVL.Out_GreenStack := TRUE;
                tonGreenDelay(IN := TRUE, PT := T#3S);
                state := GREEN_DELAY;
            END_IF
        END_IF

    GREEN_DELAY:
        tonGreenDelay(IN := TRUE, PT := T#3S);
        IF tonGreenDelay.Q THEN
            GVL.Out_GreenStack := FALSE;
            tonGreenDelay(IN := FALSE);
            GVL.Cmd_NextIndex := TRUE;      // hands control back to PLC_PRG's mover
            state := IDLE;
        END_IF

    AWAIT_ACK:
        // contextual dual-role: Inp_Red_Button.State is Stop everywhere else,
        // but read as "acknowledge" while in this state
        IF Inp_Red_Button.State THEN
            GVL.Out_RedStack := FALSE;
            GVL.Out_RedButtonLED := FALSE;
            GVL.Cmd_NextIndex := TRUE;
            state := IDLE;
        END_IF
END_CASE
```

Exact `mqttClient.Publish`/message-received call shapes will match whichever library's actual FB signatures — use the example project shipped with the library for those, the names above are illustrative.

### 5. Wiring into the existing sequencer

In `PLC_PRG`, the current "Pause before next index (Loop Up)" rung runs `TON_IndexPauseDelay` and loops straight back into the next move. Change this to: set `GVL.Sts_PositionReached` when `AMP_Relative_Move_0.Done` goes true, and gate the loop-back rung on `GVL.Cmd_NextIndex` (set by `DEFECT_CHECK` above) instead of the fixed timer. `Par_IndexPause`/`TON_IndexPauseDelay` can then either be removed or kept as a separate minimum-cycle-time guard.

### 6. Red Button — contextual three-way role (decided)

`Inp_Red_Button` now means different things depending on `machineState`/`DEFECT_CHECK.state`:

| State | Red Button means |
|---|---|
| `STANDBY` | No-op — sequence hasn't started, nothing to stop or ack. |
| `RUNNING`, not `AWAIT_ACK` | **Stop** — halts the sequence (`Cmd_Stop`/`Force_Stop`, existing behavior) and starts the 5-second return-to-Standby timer. |
| `RUNNING`, `AWAIT_ACK` | **Acknowledge** the defect — clears the red indicators and resumes to the next move. |

No new hardware input needed — same physical button, read contextually. The tradeoff: Stop is briefly unavailable while acknowledging a defect, which is deliberate for this demo, not an oversight.

### 7. `LIGHT_CYCLE` / `Green_Button_LED` changes needed

Its current button-mirroring logic conflicts with the new state-driven outputs and needs to change for four signals, not three:

- `Out_Green_Stacklight` / `Out_Red_Stacklight` / `Out_Red_Button_LED` — driven by `DEFECT_CHECK`'s state, as before.
- `Out_Yellow_Stacklight` / `Out_Green_Button_LED` — now driven by the `STANDBY` blink logic in §1 above (`OSCAT_BASIC.BLINK` output), not by whether the buttons are physically pressed.

Strip the old mirroring rungs for those specific outputs and drive them directly from the `GVL` bits set by the new top-level state machine and `DEFECT_CHECK`. Blue Button and its LED can keep their existing demo behavior, since nothing in this design uses them.

### State diagram (top-level + `DEFECT_CHECK` sub-machine)

```mermaid
stateDiagram-v2
  [*] --> STANDBY

  STANDBY : STANDBY<br/>Yellow_Stacklight blinks<br/>Green_Button_LED blinks
  STANDBY --> RUNNING : Green Button pressed<br/>stop blinking, Cmd_Run = TRUE

  state RUNNING {
    [*] --> IDLE

    IDLE --> WAITING_RESULT : Sts_PositionReached<br/>publish model/sim = "on"
    WAITING_RESULT --> GREEN_DELAY : result received<br/>defective = false<br/>Out_GreenStack = TRUE
    WAITING_RESULT --> AWAIT_ACK : result received<br/>defective = true<br/>Out_RedStack = TRUE<br/>Out_RedButtonLED = TRUE

    GREEN_DELAY --> IDLE : TON 3s elapsed<br/>Out_GreenStack = FALSE<br/>Cmd_NextIndex = TRUE

    AWAIT_ACK --> IDLE : Red Button pressed (ack)<br/>Out_RedStack = FALSE<br/>Out_RedButtonLED = FALSE<br/>Cmd_NextIndex = TRUE

    note right of AWAIT_ACK
      Inp_Red_Button is Stop everywhere
      else in RUNNING — only read as
      "acknowledge" in this state
    end note
  }

  RUNNING --> STOPPING : Red Button pressed<br/>(not in AWAIT_ACK)<br/>Cmd_Stop = TRUE
  STOPPING --> STANDBY : TON 5s elapsed<br/>clear all indicators<br/>resume blinking
```