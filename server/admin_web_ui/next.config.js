/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  distDir: 'out',
  trailingSlash: true,
  images: {
    unoptimized: true
  },
  env: {
    NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP: process.env.NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP,
    NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT: process.env.NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT,
    NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_IP: process.env.NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_IP,
    NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_PORT: process.env.NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_PORT,
  },
  // Configuración específica para Electron
  assetPrefix: process.env.NODE_ENV === 'production' ? './' : '',
  basePath: process.env.NODE_ENV === 'production' ? '' : '',
};

module.exports = nextConfig;