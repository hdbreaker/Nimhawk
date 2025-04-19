FROM ubuntu:24.04

LABEL maintainer="Alejandro Parodi (@SecSignal)"

WORKDIR /nimhawk

# Install system dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    mingw-w64 \
    nim \
    python3 \
    python3-pip \
    rustup \
    nodejs \
    npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy files first
COPY . /nimhawk

# Now ensure config.toml is present
RUN if [ -f /nimhawk/config.toml ]; then \
        echo "Config file found at /nimhawk/config.toml"; \
    else \
        echo "Config file not found, copying from example..."; \
        if [ -f /nimhawk/config.toml.example ]; then \
            cp /nimhawk/config.toml.example /nimhawk/config.toml; \
            echo "Copied config.toml.example to config.toml"; \
        else \
            echo "ERROR: No config example found either!"; \
            exit 1; \
        fi; \
    fi

# Install Python requirements
RUN pip install --no-cache-dir -r server/requirements.txt --break-system-packages

# Install Nim requirements
RUN cd implant; nimble install -d -y; cd ..

# Install Node.js requirements and build frontend
RUN cd server/admin_web_ui && npm install && npm run build

# Expose ports
# Backend API port (as configured in config.toml)
EXPOSE 9669 
# Frontend development port
EXPOSE 3000 
# HTTP Implant listener port (as configured in config.toml)
EXPOSE 80  
# HTTPS Implant listener port (optional)
EXPOSE 443  

# Create start scripts
RUN echo '#!/bin/bash\ncd /nimhawk && python3 nimhawk.py server' > /usr/local/bin/start-backend && \
    echo '#!/bin/bash\ncd /nimhawk/server/admin_web_ui && npm run dev' > /usr/local/bin/start-frontend && \
    echo '#!/bin/bash\ncd /nimhawk && python3 nimhawk.py "$@"' > /usr/local/bin/nimhawk-cli && \
    chmod +x /usr/local/bin/start-backend /usr/local/bin/start-frontend /usr/local/bin/nimhawk-cli

# Create entrypoint script
RUN echo '#!/bin/bash\n\
# Ensure configuration is available\n\
if [ ! -f /nimhawk/config.toml ]; then\n\
    echo "ERROR: config.toml not found! Starting will fail."\n\
    if [ -f /nimhawk/config.toml.example ]; then\n\
        echo "Copying example configuration..."\n\
        cp /nimhawk/config.toml.example /nimhawk/config.toml\n\
        echo "Successfully copied example configuration"\n\
    else\n\
        echo "No example configuration found either. Please provide a config.toml file."\n\
        exit 1\n\
    fi\n\
fi\n\
\n\
# Ensure XOR key persistence when running in Docker\n\
if [ "$1" = "backend" ] || [ "$1" = "all" ]; then\n\
    echo "Note: For persistent XOR keys, mount a volume at /nimhawk/.xorkey"\n\
fi\n\
\n\
if [ "$1" = "backend" ]; then\n\
    start-backend\n\
elif [ "$1" = "frontend" ]; then\n\
    start-frontend\n\
elif [ "$1" = "all" ]; then\n\
    start-backend & start-frontend\n\
else\n\
    nimhawk-cli "$@"\n\
fi' > /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command
CMD ["all"]