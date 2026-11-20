#!/bin/bash
TYPE="${1:-temp}"

sensors -j 2>/dev/null | jq --arg type "$TYPE" '
  def chipname:
    if   test("^(coretemp|k10temp|zenpower)") then "CPU"
    elif test("^(nct6|it8|w83|f71)") then "Board"
    elif test("^acpitz") then "ACPI"
    elif test("^nvme") then "NVMe"
    elif test("^pch_") then "PCH"
    elif test("^(amdgpu|nouveau|radeon)") then "GPU"
    elif test("^drivetemp") then "Disk"
    elif test("^(iwlwifi|mt7|ath)") then "Wi-Fi"
    else split("-")[0] end;
  {data: [
    to_entries[] | .key as $chip |
    .value | to_entries[] | select(.value | type == "object") | .key as $label |
    .value | keys[] | select(test("^" + $type + "[0-9]+_input$")) |
    {"{#CHIP}": $chip, "{#CHIPNAME}": ($chip | chipname), "{#LABEL}": $label, "{#SENSOR}": .}
  ]}
'
