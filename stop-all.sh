#!/bin/bash
cd ~/OMNIS_V3
if [ -f logs/app.pid ]; then kill $(cat logs/app.pid) 2>/dev/null; fi
pkill -f "start.sh" 2>/dev/null
pkill -f "python3" 2>/dev/null
rm -f logs/*.pid
echo "OMNIS_V3 stopped"
