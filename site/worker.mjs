import { marketingLocation } from './marketing-redirect.mjs';
import { createUpdateWorker } from './worker-core.mjs';

const updates = createUpdateWorker({
  canonicalHost: 'performance.daddyrad.com',
  legacyHost: 'performancedaddy.significanthobbies.com',
  pagesHost: 'performancedaddy-landing.pages.dev',
});

export default {
  /** @param {Request} request @param {Env} env */
  async fetch(request, env) {
    if (['GET', 'HEAD'].includes(request.method)) {
      const url = new URL(request.url);
      if (['performance.daddyrad.com', 'performancedaddy.significanthobbies.com'].includes(url.hostname)) {
        const marketing = marketingLocation(url.pathname, url.search, 'performance');
        if (marketing) return Response.redirect(marketing, 308);
      }
    }
    return updates.fetch(request, env);
  },
};
