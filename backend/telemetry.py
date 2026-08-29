import asyncio
import json
import logging
from .config import TELEMETRY_FILE

logger = logging.getLogger("omnis_v3")

class TelemetryBroadcaster:
    def __init__(self):
        self.connections = set()
        self.file_position = 0

    async def add_connection(self, websocket):
        self.connections.add(websocket)
        try:
            await websocket.send_text(json.dumps({"type": "connected"}))
            data = self.read_telemetry()
            if data:
                await websocket.send_text(json.dumps({"type": "telemetry", "data": data}))
            while True:
                await asyncio.sleep(2)
                new_data = self.read_telemetry()
                if new_data:
                    await websocket.send_text(json.dumps({"type": "telemetry", "data": new_data}))
        except Exception as e:
            logger.info(f"WebSocket closed: {e}")
        finally:
            self.connections.discard(websocket)

    def read_telemetry(self):
        try:
            with open(TELEMETRY_FILE, 'rb') as f:
                f.seek(self.file_position)
                lines = f.readlines()
                if not lines:
                    return None
                self.file_position = f.tell()
                data = []
                for line in lines:
                    line = line.decode(errors="replace").strip()
                    if not line:
                        continue
                    try:
                        data.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
                return data if data else None
        except FileNotFoundError:
            return None

broadcaster = TelemetryBroadcaster()
