addEventListener('memoryLanesBackgroundTick', async (resolve, reject) => {
  try {
    console.log(`[Memory Lanes] Background tick at ${new Date().toISOString()}`);

    resolve({
      ok: true,
      ranAt: new Date().toISOString()
    });
  } catch (error) {
    console.error('[Memory Lanes] Background tick failed', error);
    reject(error);
  }
});
