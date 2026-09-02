#!/bin/bash
cd ~/OMNIS_V3
pkill -f "start.sh" 2>/dev/null
pkill -f "python3" 2>/dev/null
sleep 1
mkdir -p logs
./start.sh > logs/app.log 2>&1 &
echo $! > logs/app.pid
echo "OMNIS_V3 started (PID $(cat logs/app.pid))"
