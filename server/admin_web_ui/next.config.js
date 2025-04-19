/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  distDir: 'out',
  env: {
    SERVER_IP: process.env.SERVER_IP,
    SERVER_PORT: process.env.SERVER_PORT,
    IMPLANT_SERVER_IP: process.env.IMPLANT_SERVER_IP,
    IMPLANT_SERVER_PORT: process.env.IMPLANT_SERVER_PORT,
  },
  // Other configurations
};

module.exports = nextConfig;