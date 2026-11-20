# Linux lm-sensors by Zabbix agent 2

A Zabbix 8.0 template for monitoring hardware sensors with **lm-sensors**: temperatures, fan speeds and voltages. Data is collected by Zabbix agent 2 via UserParameters (`sensors -j` + `jq`). Sensors are discovered automatically (LLD) and get readable names, e.g. `CPU Core 0: Temperature`, `Board fan2: Fan speed`, `Board Vbat: Voltage`.

## Files

| File | Purpose |
|---|---|
| `template_linux_lm_sensors_agent2.yaml` | template for import into Zabbix 8.0 |
| `discover_sensors.sh` | sensor discovery, goes to `/etc/zabbix/scripts/` |
| `get_sensor_value.sh` | sensor value readout, goes to `/etc/zabbix/scripts/` |
| `sensors.conf` | UserParameters, goes to `/etc/zabbix/zabbix_agent2.d/plugins.d/` |

## Requirements

- Zabbix server 8.0 or newer
- Zabbix agent 2 on the monitored host (passive mode)
- `lm-sensors` (`sensors -j`) and `jq`
- kernel modules loaded for the sensor chips, e.g. `coretemp`, `nct6775`

## Installation

### 1. Packages and modules (Debian/Ubuntu)

```bash
apt install lm-sensors jq
sensors-detect
```

`sensors-detect` suggests the required modules. Example for Nuvoton NCT677x, loaded at boot:

```bash
modprobe nct6775
echo nct6775 > /etc/modules-load.d/sensors.conf
sensors
```

### 2. Scripts and UserParameters

```bash
mkdir -p /etc/zabbix/scripts
install -m 0755 discover_sensors.sh get_sensor_value.sh /etc/zabbix/scripts/
install -m 0644 sensors.conf /etc/zabbix/zabbix_agent2.d/plugins.d/sensors.conf
systemctl restart zabbix-agent2
```

### 3. Test on the host

```bash
zabbix_agent2 -t sensors.discovery
zabbix_agent2 -t sensors.fan.discovery
zabbix_agent2 -t sensors.voltage.discovery
zabbix_agent2 -t 'sensor.value[coretemp-isa-0000,temp1_input]'
```

### 4. Import and linking

1. **Data collection → Templates → Import**, file `template_linux_lm_sensors_agent2.yaml`, default options.
2. Link the `Linux lm-sensors by Zabbix agent 2` template to a host with a Zabbix agent interface.
3. Optional: use **Execute now** on the host's discovery rules so you don't have to wait up to an hour for the first discovery.

> [!NOTE]
> A new version of the template imported with default options overwrites the existing template (same UUIDs). Item keys don't change, so history is preserved.

## How it works

```text
discover_sensors.sh temp|fan|in   ->  LLD: {#CHIP} {#CHIPNAME} {#LABEL} {#SENSOR}
get_sensor_value.sh CHIP SENSOR   ->  value of tempN_input / fanN_input / inN_input
```

`get_sensor_value.sh` looks up the input (e.g. `temp2_input`) within the chip regardless of the label, so changing a label doesn't break item keys.

### LLD macros

| Macro | Example | Meaning |
|---|---|---|
| `{#CHIP}` | `coretemp-isa-0000` | chip name from `sensors -j` |
| `{#CHIPNAME}` | `CPU` | friendly chip name (map in `discover_sensors.sh`) |
| `{#LABEL}` | `Core 0` | sensor label, as shown in `sensors` output |
| `{#SENSOR}` | `temp2_input` | libsensors input; together with `{#CHIP}` forms the item key |

### `{#CHIPNAME}` map

| Chip prefix | `{#CHIPNAME}` |
|---|---|
| `coretemp`, `k10temp`, `zenpower` | CPU |
| `nct6`, `it8`, `w83`, `f71` | Board |
| `acpitz` | ACPI |
| `nvme` | NVMe |
| `pch_` | PCH |
| `amdgpu`, `nouveau`, `radeon` | GPU |
| `drivetemp` | Disk |
| `iwlwifi`, `mt7`, `ath` | Wi-Fi |
| others | first part of the chip name, e.g. `jc42` |

Custom sensor names are set in the lm-sensors configuration. `sensors -j` uses them as labels, so `{#LABEL}` picks them up on the next discovery, while keys stay unchanged:

```text
# /etc/sensors.d/local.conf
chip "acpitz-acpi-0"
    label temp1 "ACPI Zone 1"
```

## Template elements

### LLD rules

| Name | Key | Interval |
|---|---|---|
| Temperature sensors discovery | `sensors.discovery` | 1h |
| Fan discovery | `sensors.fan.discovery` | 1h |
| Voltage discovery | `sensors.voltage.discovery` | 1h |

All three rules skip labels matching `{$SENSOR.LABEL.NOT_MATCHES}`.

### Item prototypes

| Name | Key | Unit |
|---|---|---|
| `{#CHIPNAME} {#LABEL}: Temperature` | `sensor.value[{#CHIP},{#SENSOR}]` | °C |
| `{#CHIPNAME} {#LABEL}: Fan speed` | `sensor.fan[{#CHIP},{#SENSOR}]` | RPM |
| `{#CHIPNAME} {#LABEL}: Voltage` | `sensor.voltage[{#CHIP},{#SENSOR}]` | V |

All: Zabbix agent type (passive), Float, 1m interval, tags `chip` and `component`.

### Trigger prototypes

| Name | Severity | Problem | Recovery |
|---|---|---|---|
| `…: Temperature is above critical threshold` | High | 5-min min > `{$SENSOR.TEMP.CRIT}` | 5-min max < threshold − 3 °C |
| `…: Temperature is above warning threshold` | Warning | 5-min min > `{$SENSOR.TEMP.WARN}` | 5-min max < threshold − 3 °C |
| `…: Fan has stopped` | Average | 0 RPM for 5 min, and the fan was spinning within the last 24 h | 5-min min > 0 |
| `…: Voltage is out of range` | Average | 5-min max < MIN or 5-min min > MAX | value returns to range |

The Warning trigger depends on High, so overheating doesn't produce two alerts. A fan that has never spun (e.g. not connected) doesn't raise an alert.

## Macros

### Temperatures and discovery filter

| Macro | Default | Description |
|---|---|---|
| `{$SENSOR.TEMP.WARN}` | `80` | Warning threshold in °C; context = chip, e.g. `{$SENSOR.TEMP.WARN:"coretemp-isa-0000"}` |
| `{$SENSOR.TEMP.CRIT}` | `85` | High threshold in °C; context = chip |
| `{$SENSOR.LABEL.NOT_MATCHES}` | value below | regex of labels skipped in all discoveries |

By default the filter skips unconnected PCH sensors on Nuvoton NCT677x (they report 0 °C):

```text
^PCH_(CHIP|CPU|MCH)_TEMP$
```

### Voltages

Thresholds are `{$SENSOR.VOLT.MIN}` and `{$SENSOR.VOLT.MAX}` with context = label (`{#LABEL}`). Common rails have regex contexts in the template with ±5% tolerance, as in the [lm-sensors example configs](https://github.com/lm-sensors/lm-sensors/tree/master/configs):

| Labels | MIN | MAX |
|---|---|---|
| `+3.3V`, `3.3V`, `+3.3Vsb`, `3VSB`, `AVCC`, `AVcc` | 3.135 | 3.465 |
| `+5V`, `5V`, `+5Vsb`, `5VSB` | 4.75 | 5.25 |
| `+12V`, `12V` | 11.4 | 12.6 |
| `Vbat`, `VBAT`, `Vbatt` | 2.8 | none |
| others (`Vcore`, `in1`, …) | -1000 | 1000 (trigger effectively disabled) |

Set a threshold for any label with a context macro on the host, e.g.:

```text
{$SENSOR.VOLT.MIN:"in1"} = 1.6
{$SENSOR.VOLT.MAX:"in1"} = 1.9
```

> [!WARNING]
> Zabbix matches exact contexts first, then regex contexts in an undefined order. Don't add regex contexts that match the same labels as existing ones. Details: [User macros with context](https://www.zabbix.com/documentation/8.0/en/manual/config/macros/user_macros_context).

## Troubleshooting

| Symptom | What to check |
|---|---|
| Item *not supported* or empty value | `sudo -u zabbix /etc/zabbix/scripts/get_sensor_value.sh <chip> <sensor>` |
| No sensors in discovery | `sudo -u zabbix /etc/zabbix/scripts/discover_sensors.sh temp` and `sensors -j` |
| Board sensors disappear after reboot | module (e.g. `nct6775`) in `/etc/modules-load.d/` |
| Agent doesn't know the new keys | `systemctl restart zabbix-agent2` |

## Notes

- Each item runs `sensors -j`. With a few dozen sensors and a 1m interval the load is negligible.
- With an active agent, change the item and LLD rule type to *Zabbix agent (active)*.
