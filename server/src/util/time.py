import datetime
from datetime import datetime
import time

# Timestamp function
TIMESTAMP_FORMAT = "%d/%m/%Y %H:%M:%S"
FILENAME_SAFE_TIMESTAMP_FORMAT = "%d-%m-%Y_%H-%M-%S"


def timestamp(filename_safe=False):
    if filename_safe:
        return datetime.now().strftime(FILENAME_SAFE_TIMESTAMP_FORMAT)
    else:
        return datetime.now().strftime(TIMESTAMP_FORMAT)

# Function to parse different timestamp formats to a datetime object
def parse_timestamp(timestamp_str):
    if not timestamp_str:
        return datetime.datetime.now()
    
    # Try common formats
    formats = [
        "%d/%m/%Y %H:%M:%S",       # DD/MM/YYYY HH:MM:SS
        "%Y-%m-%dT%H:%M:%S",       # ISO format without microseconds
        "%Y-%m-%dT%H:%M:%S.%f",    # ISO format with microseconds
        "%Y-%m-%d %H:%M:%S",       # SQL-like format
        "%Y-%m-%d"                 # Just date
    ]
    
    for fmt in formats:
        try:
            return datetime.datetime.strptime(timestamp_str, fmt)
        except ValueError:
            continue
    
    # If all formats fail, log and return current time
    print(f"Error: Could not parse timestamp: {timestamp_str}")
    return datetime.datetime.now()
