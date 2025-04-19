FROM nimlang/nim:1.6.12

LABEL maintainer="Alejandro Parodi (@SecSignal)"

WORKDIR /nimhawk

# Configurar variables para instalación no interactiva
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Instalar dependencias del sistema y Python
RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    mingw-w64 \
    ca-certificates \
    gnupg \
    unzip \
    nano \
    net-tools \
    software-properties-common \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Instalar Python 3.11 sin interacción
RUN DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y python3.11 python3.11-venv python3.11-dev \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Instalar pip de manera limpia
RUN curl -sSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
    && python3.11 /tmp/get-pip.py \
    && rm /tmp/get-pip.py

# Instalar Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copiar archivos
COPY . /nimhawk/

# Actualizar nim.cfg con rutas correctas de MinGW para Docker
RUN sed -i 's|amd64.windows.gcc.path = "/opt/homebrew/Cellar/mingw-w64/12.0.0_2/toolchain-x86_64/bin"|amd64.windows.gcc.path = "/usr/bin"|g' /nimhawk/implant/nim.cfg \
    && sed -i 's|amd64.windows.gcc.path = "/opt/homebrew/bin"|# amd64.windows.gcc.path = "/opt/homebrew/bin"|g' /nimhawk/implant/nim.cfg \
    && echo "# Docker environment MinGW configuration" >> /nimhawk/implant/nim.cfg \
    && echo "amd64.windows.gcc.path = \"/usr/bin\"" >> /nimhawk/implant/nim.cfg

# Verificar instalación de MinGW
RUN which x86_64-w64-mingw32-gcc || echo "MinGW no encontrado"

# Instalar requerimientos de Python (usando python3.11 directamente)
RUN cd /nimhawk && python3.11 -m pip install --no-cache-dir -r server/requirements.txt

# Create directories for persistence
RUN mkdir -p /nimhawk/server/downloads /nimhawk/server/logs /nimhawk/server/uploads /nimhawk/implant/release

# Ensure config.toml exists
RUN if [ ! -f /nimhawk/config.toml ]; then \
    if [ -f /nimhawk/config.toml.example ]; then \
        cp /nimhawk/config.toml.example /nimhawk/config.toml; \
        echo "Created initial config from example"; \
    else \
        echo "WARNING: No configuration template found!"; \
    fi; \
fi

# Setup permissions
RUN chmod -R 755 /nimhawk

# Instalar Nimble
RUN cd /nimhawk/implant && nimble install -y ; cd /nimhawk/

# Expose all required ports
EXPOSE 3000 9669 80 443

# Create entrypoint script
RUN echo '#!/bin/bash\n\
\n\
# Create directories if they do not exist\n\
mkdir -p /nimhawk/server/downloads /nimhawk/server/logs /nimhawk/server/uploads /nimhawk/implant/release\n\
\n\
# Ensure config.toml exists\n\
if [ ! -f /nimhawk/config.toml ]; then\n\
    if [ -f /nimhawk/config.toml.example ]; then\n\
        cp /nimhawk/config.toml.example /nimhawk/config.toml\n\
        echo "Created config from example. Please customize for production use."\n\
    else\n\
        echo "FATAL: No configuration template available."\n\
        exit 1\n\
    fi\n\
fi\n\
\n\
# Main execution logic\n\
case "$1" in\n\
    "server")\n\
        echo "Starting Nimhawk server..."\n\
        cd /nimhawk && python3 nimhawk.py server\n\
        ;;\n\
    "compile")\n\
        echo "Compiling Nimhawk implant..."\n\
        shift\n\
        cd /nimhawk && python3 nimhawk.py compile "$@"\n\
        ;;\n\
    "frontend")\n\
        echo "Starting Nimhawk frontend development server..."\n\
        cd /nimhawk/server/admin_web_ui && npm install && npm run dev\n\
        ;;\n\
    "full")\n\
        echo "Starting backend and frontend services..."\n\
        cd /nimhawk/server/admin_web_ui && npm install && npm run dev & \n\
        cd /nimhawk && python3 nimhawk.py server\n\
        ;;\n\
    "shell")\n\
        echo "Starting interactive shell..."\n\
        /bin/bash\n\
        ;;\n\
    "help")\n\
        echo "Nimhawk Docker Container"\n\
        echo "------------------------"\n\
        echo "Usage:"\n\
        echo "  server    - Start the Nimhawk server via nimhawk.py (generates .xorkey file)"\n\
        echo "  compile   - Compile implants (e.g., docker run nimhawk compile exe nim-debug)"\n\
        echo "  frontend  - Start only the frontend dev server"\n\
        echo "  full      - Start both backend and frontend servers"\n\
        echo "  shell     - Start an interactive shell"\n\
        echo "  help      - Show this help message"\n\
        ;;\n\
    *)\n\
        echo "Command not recognized. Run 'help' for available commands."\n\
        exit 1\n\
        ;;\n\
esac' > /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command (server if no command specified)
CMD ["server"]
