if ('serviceWorker' in navigator && window.isSecureContext) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js', { scope: './' }).catch(() => {
      // No financial data is logged. The app remains usable online, but cannot
      // claim offline availability until this registration succeeds.
      document.dispatchEvent(new CustomEvent('offline-unavailable'));
    });
  });
}
