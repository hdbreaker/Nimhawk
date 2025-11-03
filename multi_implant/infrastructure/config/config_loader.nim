#[
    Config Loader: Infrastructure Configuration
    Wraps the existing config_parser for infrastructure layer
    Re-exports configuration parsing functionality
]#

# Import and re-export from config_parser (now in same directory)
import config_parser
export parseConfig, INITIAL_XOR_KEY
