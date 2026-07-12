import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'app.memorylanes.ridejournal',
  appName: 'Memory Lanes',
  webDir: 'www',
  plugins: {
    BackgroundRunner: {
      label: 'app.memorylanes.background.task',
      src: 'runners/background.js',
      event: 'memoryLanesBackgroundTick',
      repeat: true,
      interval: 15,
      autoStart: true
    }
  },
  ios: {
    contentInset: 'automatic'
  }
};

export default config;
