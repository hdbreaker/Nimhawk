"""
Dynamic Implants Server Proxy Module

This module automatically detects routes from the Implants Server (implants_server_init.py)
and creates proxy endpoints in the Admin API, enabling machine-to-machine communication
without duplicating endpoint definitions.

Architecture:
Nimhawk Client <---> Admin API <---> Implants Server Proxy <---> Implants Server <---> Implants

Benefits:
- Single client endpoint (Admin API only)
- Automatic route detection and scaling
- Centralized authentication and logging
- Machine-to-machine security between Admin API and Implants Server
"""

import ast
import os
import re
import requests
import flask
from typing import Dict, List, Tuple, Optional
import src.util.utils as utils
from src.config.config import config


class ImplantsServerProxy:
    """
    Dynamic proxy that automatically detects Implants Server routes and forwards requests
    """
    
    def __init__(self):
        self.implants_server_base_url = self._get_implants_server_url()
        self.detected_routes = []
        self.m2m_token = self._generate_m2m_token()
        
    def _get_implants_server_url(self) -> str:
        """Get Implants Server URL from config"""
        try:
            protocol = "https" if config["implants_server"]["type"] == "HTTPS" else "http"
            ip = config["implants_server"].get("ip", "127.0.0.1")
            port = config["implants_server"]["port"]
            return f"{protocol}://{ip}:{port}"
        except KeyError as e:
            utils.nimplant_print(f"ERROR: Missing Implants Server config: {e}")
            return "http://127.0.0.1:80"
    
    def _generate_m2m_token(self) -> str:
        """Generate machine-to-machine authentication token"""
        # Use the same key from config for M2M auth
        return config["implant"]["httpAllowCommunicationKey"]
    
    def detect_implants_server_routes(self) -> List[Dict]:
        """
        Automatically detect routes from implants_server_init.py
        Returns list of route definitions with methods and paths
        """
        routes = []
        
        try:
            # Get path to implants_server_init.py
            current_dir = os.path.dirname(os.path.abspath(__file__))
            implants_server_path = os.path.join(
                current_dir, "..", "..", "implants_api", "implants_server_init.py"
            )
            
            utils.nimplant_print(f"DEBUG: Scanning Implants Server routes from: {implants_server_path}")
            
            with open(implants_server_path, 'r') as f:
                content = f.read()
            
            # Parse AST to find route decorators
            tree = ast.parse(content)
            
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef):
                    # Check if function has @app.route decorator
                    for decorator in node.decorator_list:
                        if (isinstance(decorator, ast.Call) and 
                            isinstance(decorator.func, ast.Attribute) and
                            decorator.func.attr == 'route'):
                            
                            # Extract route path and methods
                            route_path = None
                            methods = ['GET']  # Default method
                            
                            # Get route path (first argument)
                            if decorator.args:
                                if isinstance(decorator.args[0], ast.Constant):
                                    route_path = decorator.args[0].value
                                elif isinstance(decorator.args[0], ast.Name):
                                    # Handle variable references like register_path
                                    route_path = self._resolve_config_variable(decorator.args[0].id)
                                elif isinstance(decorator.args[0], ast.BinOp):
                                    # Handle concatenations like task_path + "/<file_id>"
                                    route_path = self._resolve_binary_operation(decorator.args[0])
                            
                            # Get methods from keyword arguments
                            for keyword in decorator.keywords:
                                if keyword.arg == 'methods':
                                    if isinstance(keyword.value, ast.List):
                                        methods = [elt.value for elt in keyword.value.elts 
                                                 if isinstance(elt, ast.Constant)]
                            
                            if route_path:
                                route_info = {
                                    'path': route_path,
                                    'methods': methods,
                                    'function_name': node.name,
                                    'proxy_needed': self._should_proxy_route(route_path)
                                }
                                routes.append(route_info)
                                utils.nimplant_print(
                                    f"DEBUG: Detected route: {route_path} "
                                    f"[{', '.join(methods)}] -> {node.name}"
                                )
            
        except Exception as e:
            utils.nimplant_print(f"ERROR: Failed to detect Implants Server routes: {e}")
            import traceback
            utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
        
        self.detected_routes = routes
        return routes
    
    def _resolve_config_variable(self, var_name: str) -> Optional[str]:
        """Resolve config variables like register_path, task_path, etc."""
        config_mapping = {
            'register_path': config["implants_server"]["registerPath"],
            'task_path': config["implants_server"]["taskPath"],
            'resultPath': config["implants_server"]["resultPath"],
            'reconnectPath': config["implants_server"]["reconnectPath"],
        }
        return config_mapping.get(var_name)
    
    def _resolve_binary_operation(self, node: ast.BinOp) -> Optional[str]:
        """Resolve binary operations like task_path + "/<file_id>" """
        if isinstance(node.op, ast.Add):
            left = ""
            right = ""
            
            if isinstance(node.left, ast.Name):
                left = self._resolve_config_variable(node.left.id) or ""
            elif isinstance(node.left, ast.Constant):
                left = node.left.value
                
            if isinstance(node.right, ast.Constant):
                right = node.right.value
                
            return left + right
        return None
    
    def _should_proxy_route(self, route_path: str) -> bool:
        """Determine if a route should be proxied to Admin API"""
        # Routes that need proxying (implant communication routes)
        proxy_routes = [
            config["implants_server"]["registerPath"],
            config["implants_server"]["taskPath"],
            config["implants_server"]["resultPath"],
            config["implants_server"]["reconnectPath"],
        ]
        
        # Check if route starts with any proxy route
        for proxy_route in proxy_routes:
            if route_path.startswith(proxy_route):
                return True
                
        return False
    
    def create_proxy_endpoints(self, app: flask.Flask, require_auth_decorator):
        """
        Create proxy endpoints in the Admin API Flask app
        """
        routes = self.detect_implants_server_routes()
        
        for route_info in routes:
            if not route_info['proxy_needed']:
                continue
                
            path = route_info['path']
            methods = route_info['methods']
            
            # Create proxy endpoint
            proxy_endpoint = self._create_proxy_function(path, methods)
            
            # Register the route in Flask app
            endpoint_name = f"proxy_{route_info['function_name']}"
            
            # Apply authentication decorator
            decorated_endpoint = require_auth_decorator(proxy_endpoint)
            
            app.add_url_rule(
                path,
                endpoint=endpoint_name,
                view_func=decorated_endpoint,
                methods=methods
            )
            
            utils.nimplant_print(
                f"DEBUG: Created proxy endpoint: {path} "
                f"[{', '.join(methods)}] -> {endpoint_name}"
            )
    
    def _create_proxy_function(self, path: str, methods: List[str]):
        """
        Create a proxy function that forwards requests to Implants Server
        """
        def proxy_endpoint(**kwargs):
            try:
                # Build target URL
                target_url = self.implants_server_base_url + flask.request.path
                
                utils.nimplant_print(
                    f"DEBUG: Proxying {flask.request.method} {flask.request.path} -> {target_url}"
                )
                
                # Prepare headers for Implants Server
                headers = dict(flask.request.headers)
                
                # Add machine-to-machine authentication
                headers['X-Correlation-ID'] = self.m2m_token
                
                # Ensure User-Agent matches expected value
                headers['User-Agent'] = config["implant"]["userAgent"]
                
                # Forward request based on method
                if flask.request.method == 'GET':
                    response = requests.get(
                        target_url,
                        headers=headers,
                        params=flask.request.args,
                        timeout=30
                    )
                elif flask.request.method == 'POST':
                    response = requests.post(
                        target_url,
                        headers=headers,
                        json=flask.request.get_json() if flask.request.is_json else None,
                        data=flask.request.data if not flask.request.is_json else None,
                        params=flask.request.args,
                        timeout=30
                    )
                elif flask.request.method == 'OPTIONS':
                    response = requests.options(
                        target_url,
                        headers=headers,
                        timeout=30
                    )
                else:
                    return flask.jsonify({'error': f'Method {flask.request.method} not supported'}), 405
                
                utils.nimplant_print(
                    f"DEBUG: Implants Server response: {response.status_code} "
                    f"(Content-Length: {len(response.content)})"
                )
                
                # Create response
                proxy_response = flask.make_response(response.content, response.status_code)
                
                # Copy response headers (excluding some that Flask handles)
                excluded_headers = {'content-length', 'content-encoding', 'transfer-encoding', 'connection'}
                for key, value in response.headers.items():
                    if key.lower() not in excluded_headers:
                        proxy_response.headers[key] = value
                
                return proxy_response
                
            except requests.exceptions.ConnectionError:
                utils.nimplant_print(f"ERROR: Cannot connect to Implants Server at {self.implants_server_base_url}")
                return flask.jsonify({
                    'error': 'Implants Server unavailable',
                    'message': 'Cannot connect to implants server'
                }), 503
                
            except requests.exceptions.Timeout:
                utils.nimplant_print(f"ERROR: Timeout connecting to Implants Server")
                return flask.jsonify({
                    'error': 'Implants Server timeout',
                    'message': 'Request to implants server timed out'
                }), 504
                
            except Exception as e:
                utils.nimplant_print(f"ERROR: Proxy error: {e}")
                import traceback
                utils.nimplant_print(f"Traceback: {traceback.format_exc()}")
                return flask.jsonify({
                    'error': 'Proxy error',
                    'message': str(e)
                }), 500
        
        return proxy_endpoint
    
    def health_check(self) -> bool:
        """Check if Implants Server is available"""
        try:
            response = requests.get(f"{self.implants_server_base_url}/alive", timeout=5)
            return response.status_code == 200
        except:
            return False


# Global proxy instance
implants_server_proxy = ImplantsServerProxy() 