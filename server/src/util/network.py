from flask import Request

# Define a utility function to easily get the 'real' IP from a request
def get_external_ip(request: Request):
    if request.headers.get("X-Forwarded-For"):
        return request.access_route[0]
    else:
        return request.remote_addr