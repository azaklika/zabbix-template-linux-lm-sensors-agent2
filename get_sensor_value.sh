#!/bin/bash
CHIP="$1"
SENSOR="$2"

sensors -j 2>/dev/null | jq -r --arg chip "$CHIP" --arg sensor "$SENSOR" '
  first(.[$chip] | .. | objects | .[$sensor] // empty)
'
