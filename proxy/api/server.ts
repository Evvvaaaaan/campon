import { createServer } from 'node:http';

import { searchCampsiteImages } from './_campsite_image.ts';
import { searchCampsiteReservation } from './_campsite_reservation.ts';

const port = Number.parseInt(process.env.PORT ?? '8080', 10);

createServer(async (request, response) => {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  response.setHeader('Content-Type', 'application/json; charset=utf-8');

  if (request.method === 'OPTIONS') {
    response.writeHead(204).end();
    return;
  }

  const url = new URL(request.url ?? '/', 'http://localhost');
  if (request.method === 'GET' && url.pathname === '/health') {
    response.writeHead(200).end(JSON.stringify({ status: 'ok' }));
    return;
  }
  if (
    request.method !== 'GET' ||
    !['/api/campsite-image', '/api/campsite-reservation'].includes(url.pathname)
  ) {
    response.writeHead(404).end(JSON.stringify({ error: 'not found' }));
    return;
  }

  const name = url.searchParams.get('name') ?? '';
  if (!name.trim()) {
    response.writeHead(400).end(
      JSON.stringify({ images: [], error: 'name is required' }),
    );
    return;
  }

  try {
    if (url.pathname === '/api/campsite-reservation') {
      const result = await searchCampsiteReservation(name);
      response.writeHead(200).end(JSON.stringify(result));
      return;
    }
    const result = await searchCampsiteImages(
      name,
      url.searchParams.get('region') ?? undefined,
    );
    response.writeHead(200).end(JSON.stringify(result));
  } catch (error) {
    response.writeHead(502).end(
      JSON.stringify({ images: [], reservation: null, error: String(error) }),
    );
  }
}).listen(port, '0.0.0.0', () => {
  console.log(`[campsite-image] listening on :${port}`);
});
