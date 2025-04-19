from dataclasses import dataclass
from datetime import datetime
from typing import Optional

# Common class for db.py and nimplant_listener_model.py
@dataclass
class Server:
    guid: str = None
    name: str = None
    date_created: datetime = None
    xor_key: int = None
    management_ip: str = None
    management_port: int = None
    listener_type: str = None
    server_ip: str = None
    listener_host: str = None
    listener_port: int = None
    register_path: str = None
    task_path: str = None
    result_path: str = None
    reconnect_path: str = None
    risky_mode: bool = False
    sleep_time: int = None
    sleep_jitter: int = None
    kill_date: Optional[str] = None
    user_agent: str = None
    http_allow_communication_key: str = None
    killed: bool = False 