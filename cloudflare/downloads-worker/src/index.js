export default {
  async fetch(request, env) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', {
        status: 405,
        headers: {Allow: 'GET, HEAD'},
      });
    }

    const url = new URL(request.url);
    const key = url.pathname.replace(/^\/+/, '');
    if (!key.startsWith('mac/') || key.includes('..')) {
      return new Response('Not Found', {status: 404});
    }

    if (request.method === 'HEAD') {
      const object = await env.DOWNLOADS.head(key);
      if (object === null) {
        return new Response(null, {status: 404});
      }
      const headers = responseHeaders(object, key);
      headers.set('content-length', object.size.toString());
      return new Response(null, {status: 200, headers});
    }

    const object = await env.DOWNLOADS.get(key, {
      onlyIf: request.headers,
      range: request.headers,
    });
    if (object === null) {
      return new Response('Not Found', {status: 404});
    }

    const headers = responseHeaders(object, key);
    if (!('body' in object)) {
      return new Response(null, {status: 412, headers});
    }

    let status = 200;
    if (object.range !== undefined) {
      const offset = object.range.offset ?? 0;
      const length = object.range.length ?? object.size;
      headers.set(
        'content-range',
        `bytes ${offset}-${offset + length - 1}/${object.size}`,
      );
      headers.set('content-length', length.toString());
      status = 206;
    } else {
      headers.set('content-length', object.size.toString());
    }

    return new Response(object.body, {status, headers});
  },
};

function responseHeaders(object, key) {
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  if (key.endsWith('.dmg')) {
    headers.set('content-type', 'application/x-apple-diskimage');
    headers.set('content-disposition', 'attachment; filename="Mixroom-macOS.dmg"');
    headers.set('cache-control', 'public, max-age=300, must-revalidate');
  } else if (key.endsWith('.zip')) {
    headers.set('content-type', 'application/zip');
    headers.set('cache-control', 'public, max-age=31536000, immutable');
  } else if (key.endsWith('.xml')) {
    headers.set('content-type', 'application/rss+xml; charset=utf-8');
    headers.set('cache-control', 'no-cache, max-age=0, must-revalidate');
  }
  headers.set('accept-ranges', 'bytes');
  headers.set('etag', object.httpEtag);
  headers.set('x-content-type-options', 'nosniff');
  return headers;
}
