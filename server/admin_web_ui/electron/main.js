const { app, BrowserWindow, Menu, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const isDev = process.env.NODE_ENV === 'development';

// Mantener una referencia global del objeto de ventana
let mainWindow;

function createWindow() {
  // Crear la ventana del navegador
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      enableRemoteModule: false,
      webSecurity: !isDev
    },
    icon: path.join(__dirname, '../public/favicon.ico'), // Asegurate de tener un favicon
    titleBarStyle: 'default',
    show: false // No mostrar hasta que esté listo
  });

  // Determinar la URL a cargar
  const staticIndexPath = path.join(__dirname, '../out/index.html');
  
  console.log('isDev:', isDev);
  console.log('NODE_ENV:', process.env.NODE_ENV);
  console.log('app.isPackaged:', app.isPackaged);
  
  if (isDev) {
    // Modo desarrollo: usar servidor de desarrollo
    const startUrl = 'http://localhost:3000';
    console.log('Loading URL:', startUrl);
    mainWindow.loadURL(startUrl);
  } else {
    // Modo producción: usar archivos estáticos
    if (fs.existsSync(staticIndexPath)) {
      const indexURL = `file://${staticIndexPath}`;
      console.log('Loading URL:', indexURL);
      mainWindow.loadURL(indexURL);
    } else {
      console.error('Static files not found. Please run "npm run build" first.');
      app.quit();
      return;
    }
  }

  // Mostrar ventana cuando esté lista
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  // Abrir DevTools en desarrollo
  if (isDev) {
    mainWindow.webContents.openDevTools();
  }

  // Manejar enlaces externos
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  // Interceptar navegación en modo producción para manejar rutas de SPA
  if (!isDev) {
    mainWindow.webContents.on('will-navigate', (event, navigationUrl) => {
      const parsedUrl = new URL(navigationUrl);
      
      if (parsedUrl.protocol === 'file:') {
        event.preventDefault();
        
        // Extraer la ruta de la URL
        let route = parsedUrl.pathname;
        if (route === '/' || route === '') {
          route = '/index.html';
        } else if (!route.endsWith('.html') && !route.includes('.')) {
          // Si es una ruta de página sin extensión, agregar /index.html
          route = route.endsWith('/') ? route + 'index.html' : route + '/index.html';
        }
        
        const filePath = path.join(__dirname, '../out', route);
        
        if (fs.existsSync(filePath)) {
          mainWindow.loadFile(filePath);
        } else {
          // Si el archivo no existe, cargar la página 404 o index
          const indexPath = path.join(__dirname, '../out/index.html');
          if (fs.existsSync(indexPath)) {
            mainWindow.loadFile(indexPath);
          }
        }
      }
    });

    // Interceptar peticiones de recursos para servir archivos estáticos
    const { session } = require('electron');
    session.defaultSession.protocol.interceptFileProtocol('file', (request, callback) => {
      const url = request.url.substr(7); // quitar "file://"
      
      // Si es una petición de imagen o recurso estático
      if (url.match(/\.(png|jpg|jpeg|gif|svg|ico|css|js)$/)) {
        const fileName = path.basename(url);
        const staticFilePath = path.join(__dirname, '../out', fileName);
        
        if (fs.existsSync(staticFilePath)) {
          callback({ path: staticFilePath });
          return;
        }
      }
      
      // Para todo lo demás, usar el comportamiento por defecto
      callback({ path: url });
    });
  }

  // Manejar refresh (F5, Cmd+R) en modo producción
  if (!isDev) {
    const handleRefresh = () => {
      const currentURL = mainWindow.webContents.getURL();
      console.log('Refresh detected, current URL:', currentURL);
      
      // Siempre cargar el index.html principal y luego navegar con JavaScript
      const indexPath = path.join(__dirname, '../out/index.html');
      const indexURL = `file://${indexPath}`;
      
      // Extraer la ruta que queremos
      let targetRoute = '/';
      if (currentURL.startsWith('file://')) {
        const urlPath = new URL(currentURL).pathname;
        
        if (urlPath.includes('/login')) {
          targetRoute = '/login';
        } else if (urlPath.includes('/server')) {
          targetRoute = '/server';
        } else if (urlPath.includes('/implants')) {
          targetRoute = '/implants';
        } else if (urlPath.includes('/downloads')) {
          targetRoute = '/downloads';
        }
      }
      
      console.log('Target route:', targetRoute);
      console.log('Loading index and navigating to:', targetRoute);
      
      // Cargar index.html
      mainWindow.loadURL(indexURL).then(() => {
        // Después de cargar, navegar a la ruta correcta si no es la raíz
        if (targetRoute !== '/') {
          setTimeout(() => {
            mainWindow.webContents.executeJavaScript(`
              if (window.location.pathname !== '${targetRoute}') {
                console.log('Navigating to: ${targetRoute}');
                if (window.history && window.history.pushState) {
                  window.history.pushState({}, '', '${targetRoute}');
                  window.dispatchEvent(new PopStateEvent('popstate'));
                } else if (window.location) {
                  window.location.hash = '${targetRoute}';
                }
              }
            `);
          }, 500);
        }
      }).catch(err => {
        console.error('Error loading index:', err);
      });
    };

    mainWindow.webContents.on('before-input-event', (event, input) => {
      // Detectar Cmd+R (macOS), Ctrl+R (Windows/Linux), o F5
      if ((input.meta && input.key === 'r') || 
          (input.control && input.key === 'r') || 
          input.key === 'F5') {
        event.preventDefault();
        handleRefresh();
      }
    });

    // También interceptar el evento de reload del webContents
    mainWindow.webContents.on('did-fail-load', (event, errorCode, errorDescription, validatedURL) => {
      console.log('Failed to load:', validatedURL, 'Error:', errorDescription);
      if (validatedURL.startsWith('file:///') && !validatedURL.includes('out')) {
        // Si falló cargar una URL de file:// que no incluye 'out', intentar con nuestra lógica
        handleRefresh();
      }
    });
  }

  // Evento cuando la ventana es cerrada
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// Este método será llamado cuando Electron haya terminado de inicializarse
app.whenReady().then(createWindow);

// Salir cuando todas las ventanas están cerradas
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (mainWindow === null) {
    createWindow();
  }
});

// Crear menú de aplicación
const template = [
  {
    label: 'Archivo',
    submenu: [
      {
        label: 'Recargar',
        accelerator: 'CmdOrCtrl+R',
        click: () => {
          if (mainWindow) {
            if (isDev) {
              mainWindow.reload();
            } else {
                             // En producción, usar la misma lógica de refresh personalizada
               handleRefresh();
            }
          }
        }
      },
      {
        label: 'Herramientas de Desarrollador',
        accelerator: 'F12',
        click: () => {
          if (mainWindow) {
            mainWindow.webContents.toggleDevTools();
          }
        }
      },
      { type: 'separator' },
      {
        label: 'Salir',
        accelerator: process.platform === 'darwin' ? 'Cmd+Q' : 'Ctrl+Q',
        click: () => {
          app.quit();
        }
      }
    ]
  },
  {
    label: 'Ver',
    submenu: [
      {
        label: 'Zoom In',
        accelerator: 'CmdOrCtrl+Plus',
        click: () => {
          if (mainWindow) {
            const currentZoom = mainWindow.webContents.getZoomLevel();
            mainWindow.webContents.setZoomLevel(currentZoom + 0.5);
          }
        }
      },
      {
        label: 'Zoom Out',
        accelerator: 'CmdOrCtrl+-',
        click: () => {
          if (mainWindow) {
            const currentZoom = mainWindow.webContents.getZoomLevel();
            mainWindow.webContents.setZoomLevel(currentZoom - 0.5);
          }
        }
      },
      {
        label: 'Reset Zoom',
        accelerator: 'CmdOrCtrl+0',
        click: () => {
          if (mainWindow) {
            mainWindow.webContents.setZoomLevel(0);
          }
        }
      }
    ]
  }
];

if (process.platform === 'darwin') {
  template.unshift({
    label: app.getName(),
    submenu: [
      { role: 'about' },
      { type: 'separator' },
      { role: 'services' },
      { type: 'separator' },
      { role: 'hide' },
      { role: 'hideothers' },
      { role: 'unhide' },
      { type: 'separator' },
      { role: 'quit' }
    ]
  });
}

const menu = Menu.buildFromTemplate(template);
Menu.setApplicationMenu(menu); 