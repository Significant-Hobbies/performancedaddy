const routes = new Map([
  ['/', '/'],
  ['/index.html', '/'],
  ['/index.md', '/index.md'],
  ['/llms.txt', '/llms.txt'],
  ['/llms-full.txt', '/llms-full.txt'],
  ['/ai.txt', '/ai.txt'],
  ['/sitemap.xml', '/sitemap.xml'],
  ['/blog/rss.xml', '/blog/rss.xml'],
]);
for (const section of ['privacy', 'terms', 'support', 'accessibility', 'release', 'testflight', 'blog']) {
  routes.set(`/${section}`, `/${section}/`);
  routes.set(`/${section}/`, `/${section}/`);
  routes.set(`/${section}/index.html`, `/${section}/`);
  routes.set(`/${section}/index.md`, `/${section}/index.md`);
  routes.set(`/${section}.md`, `/${section}/index.md`);
}

for (const path of ['/blog/background-apps', '/blog/background-apps/', '/blog/background-apps/index.html']) {
  routes.set(path, '/blog/background-apps/');
}
for (const path of ['/blog/background-apps.md', '/blog/background-apps/index.md']) {
  routes.set(path, '/blog/background-apps/index.md');
}

/** @param {string} path @param {string} search @param {string} mount */
export function marketingLocation(path, search, mount) {
  const target = routes.get(path);
  return target === undefined ? null : `https://daddyrad.com/${mount}${target}${search}`;
}
