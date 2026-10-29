import { createUpdateWorker } from './worker-core.mjs';

export default createUpdateWorker({
  marketingMount: 'performance',
  canonicalHost: 'performance.daddyrad.com',
  legacyHost: 'performancedaddy.significanthobbies.com',
  pagesHost: 'performancedaddy-landing.pages.dev',
});
