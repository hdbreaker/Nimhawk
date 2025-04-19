import flask
import json
from enum import unique, Enum
from typing import Optional

from src.util.network import get_external_ip
import src.util.utils as utils

@unique
class BadRequestReason(Enum):
    BAD_KEY = "bad_key"
    UNKNOWN = "unknown"
    NO_TASK_GUID = "no_task_id"
    ID_NOT_FOUND = "id_not_found"
    NOT_RECEIVING_FILE = "not_receiving_file"
    NOT_HOSTING_FILE = "not_hosting_file"
    INCORRECT_FILE_ID = "incorrect_file_id"
    USER_AGENT_MISMATCH = "user_agent_mismatch"

    def get_explanation(self):
        explanations = {
            self.BAD_KEY: "We were unable to process the request. This is likely caused by a XOR key mismatch between Implant and server! It could be an old Implant that wasn't properly killed or blue team activity.",
            self.NO_TASK_GUID: "No task GUID was given. This could indicate blue team activity or random internet noise.",
            self.ID_NOT_FOUND: "The specified Implant ID was not found. This could indicate an old Implant trying to reconnect, blue team activity, or random internet noise.",
            self.NOT_RECEIVING_FILE: "We've received an unexpected file upload request from a Implant. This could indicate a mismatch between the server and the Implant or blue team activity.",
            self.NOT_HOSTING_FILE: "We've received an unexpected file download request from a Implant. This could indicate a mismatch between the server and the Implant or blue team activity.",
            self.INCORRECT_FILE_ID: "The specified file id for upload/download is incorrect. This could indicate a mismatch between the server and the Implant or blue team activity.",
            self.USER_AGENT_MISMATCH: "User-Agent for the request doesn't match the configuration. This could indicate an old Implant trying to reconnect, blue team activity, or random internet noise.",
            self.UNKNOWN: "The reason is unknown.",
        }

        return explanations.get(self, "The reason is unknown.")


# Define a function to notify users of unknown or erroneous requests
def notify_bad_request(
    request: flask.Request,
    reason: BadRequestReason = BadRequestReason.UNKNOWN,
    np_guid: Optional[str] = None,
):
    source = get_external_ip(request)
    headers = dict(request.headers)
    user_agent = request.headers.get("User-Agent", "Unknown")

    utils.nimplant_print(
        f"Rejected {request.method} request from '{source}': {request.path} ({user_agent})",
        target=np_guid,
    )
    utils.nimplant_print(f"Reason: {reason.get_explanation()}", target=np_guid)

    # Printing headers would be useful for checking if we have id or guid definitions.
    utils.nimplant_print("Request Headers:", target=np_guid)
    utils.nimplant_print(json.dumps(headers, ensure_ascii=False), target=np_guid)
