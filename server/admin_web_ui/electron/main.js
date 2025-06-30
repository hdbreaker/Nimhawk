const { app, BrowserWindow, Menu, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const isDev = process.env.NODE_ENV === 'development';

// Keep a global reference of the window object
let mainWindow;

function createWindow() {
  // Create the browser window
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
    icon: path.join(__dirname, '../public/favicon.ico'), // Make sure you have a favicon
    titleBarStyle: 'default',
    show: false // Don't show until ready
  });

  // Determine the URL to load
  const staticIndexPath = path.join(__dirname, '../out/index.html');
  
  console.log('isDev:', isDev);
  console.log('NODE_ENV:', process.env.NODE_ENV);
  console.log('app.isPackaged:', app.isPackaged);
  
  if (isDev) {
    // Development mode: use development server
    const startUrl = 'http://localhost:3000';
    console.log('Loading URL:', startUrl);
    mainWindow.loadURL(startUrl);
  } else {
    // Production mode: use static files
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

  // Show window when ready
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  // Open DevTools in development
  if (isDev) {
    mainWindow.webContents.openDevTools();
  }

  // Handle external links
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  // Intercept navigation in production mode to handle SPA routes
  if (!isDev) {
    mainWindow.webContents.on('will-navigate', (event, navigationUrl) => {
      const parsedUrl = new URL(navigationUrl);
      
      if (parsedUrl.protocol === 'file:') {
        event.preventDefault();
        
        // Extract route from URL
        let route = parsedUrl.pathname;
        if (route === '/' || route === '') {
          route = '/index.html';
        } else if (!route.endsWith('.html') && !route.includes('.')) {
          // If it's a page route without extension, add /index.html
          route = route.endsWith('/') ? route + 'index.html' : route + '/index.html';
        }
        
        const filePath = path.join(__dirname, '../out', route);
        
        if (fs.existsSync(filePath)) {
          mainWindow.loadFile(filePath);
        } else {
          // If file doesn't exist, load 404 page or index
          const indexPath = path.join(__dirname, '../out/index.html');
          if (fs.existsSync(indexPath)) {
            mainWindow.loadFile(indexPath);
          }
        }
      }
    });

    // Intercept resource requests to serve static files
    const { session } = require('electron');
    session.defaultSession.protocol.interceptFileProtocol('file', (request, callback) => {
      const url = request.url.substr(7); // remove "file://"
      
      // If it's an image or static resource request
      if (url.match(/\.(png|jpg|jpeg|gif|svg|ico|css|js)$/)) {
        const fileName = path.basename(url);
        const staticFilePath = path.join(__dirname, '../out', fileName);
        
        if (fs.existsSync(staticFilePath)) {
          callback({ path: staticFilePath });
          return;
        }
      }
      
      // For everything else, use default behavior
      callback({ path: url });
    });
  }

  // Handle refresh (F5, Cmd+R) in production mode
  let handleRefresh; // Declare at module level
  
  if (!isDev) {
    handleRefresh = () => {
      const currentURL = mainWindow.webContents.getURL();
      console.log('Refresh detected, current URL:', currentURL);
      
      // Always load main index.html and then navigate with JavaScript
      const indexPath = path.join(__dirname, '../out/index.html');
      const indexURL = `file://${indexPath}`;
      
      // Extract the route we want
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
      
      // Load index.html
      mainWindow.loadURL(indexURL).then(() => {
        // After loading, navigate to the correct route if it's not root
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
      // Detect Cmd+R (macOS), Ctrl+R (Windows/Linux), or F5
      if ((input.meta && input.key === 'r') || 
          (input.control && input.key === 'r') || 
          input.key === 'F5') {
        event.preventDefault();
        handleRefresh();
      }
    });

    // Also intercept webContents reload event
    mainWindow.webContents.on('did-fail-load', (event, errorCode, errorDescription, validatedURL) => {
      console.log('Failed to load:', validatedURL, 'Error:', errorDescription);
      if (validatedURL.startsWith('file:///') && !validatedURL.includes('out')) {
        // If failed to load a file:// URL that doesn't include 'out', try with our logic
        handleRefresh();
      }
    });
  }

  // Event when window is closed
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// This method will be called when Electron has finished initializing
app.whenReady().then(createWindow);

// Quit when all windows are closed
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

// Create application menu
const template = [
  {
    label: 'File',
    submenu: [
      {
        label: 'Reload',
        accelerator: 'CmdOrCtrl+R',
        click: () => {
          if (mainWindow) {
            if (isDev) {
              mainWindow.reload();
            } else {
              // In production, use the same custom refresh logic
              handleRefresh();
            }
          }
        }
      },
      {
        label: 'Developer Tools',
        accelerator: 'F12',
        click: () => {
          if (mainWindow) {
            mainWindow.webContents.toggleDevTools();
          }
        }
      },
      { type: 'separator' },
      {
        label: 'Exit',
        accelerator: process.platform === 'darwin' ? 'Cmd+Q' : 'Ctrl+Q',
        click: () => {
          app.quit();
        }
      }
    ]
  },
  {
    label: 'View',
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