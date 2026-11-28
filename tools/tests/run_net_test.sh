#!/bin/bash
# Two headless instances (host + client) play a mini LAN match. Usage: run_net_test.sh [project_dir]
P=${1:-.}
GODOT=${GODOT:-godot}
$GODOT --headless --path "$P" res://test_net.tscn -- --role=host > /tmp/net_host.log 2>&1 &
H=$!
sleep 3
$GODOT --headless --path "$P" res://test_net.tscn -- --role=client > /tmp/net_client.log 2>&1 &
C=$!
wait $H; HE=$?
wait $C; CE=$?
grep -hE "^(PASS|FAIL|RESULT)" /tmp/net_host.log /tmp/net_client.log
echo "host exit $HE, client exit $CE"
[ $HE -eq 0 ] && [ $CE -eq 0 ]
