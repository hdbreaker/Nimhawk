from src.servers.admin_api.models.nimplant_listener_model import np_server
from time import sleep

# Loop to check for late checkins (can be infinite - runs as separate thread)
def periodic_implant_checks():
    while True:
        np_server.check_late_nimplants()
        sleep(5)