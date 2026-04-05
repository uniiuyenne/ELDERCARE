/**
 * PM2 ecosystem config for ElderCare notification daemon.
 *
 * Usage:
 *  - npm run build
 *  - pm2 start ecosystem.config.cjs
 */

module.exports = {
  apps: [
    {
      name: 'eldercare-daemon',
      cwd: __dirname,
      script: 'dist/index.js',
      interpreter: 'node',
      env_file: '.env',
      env: {
        NODE_ENV: 'production',
      },
      autorestart: true,
      max_restarts: 20,
      restart_delay: 2000,
      time: true,
      out_file: 'logs/out.log',
      error_file: 'logs/err.log',
      merge_logs: true,
    },
  ],
};
