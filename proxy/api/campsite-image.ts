import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';

import { searchCampsiteImages } from './_campsite_image.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

export async function campsiteImageHandler(
  request: HttpRequest,
  _context: InvocationContext,
): Promise<HttpResponseInit> {
  if (request.method === 'OPTIONS') return { status: 204, headers: cors };
  const name = request.query.get('name') ?? '';
  const region = request.query.get('region') ?? undefined;
  if (!name.trim()) {
    return {
      status: 400,
      jsonBody: { images: [], error: 'name is required' },
      headers: cors,
    };
  }
  try {
    const result = await searchCampsiteImages(name, region);
    return { status: 200, jsonBody: result, headers: cors };
  } catch (error) {
    return {
      status: 502,
      jsonBody: { images: [], error: String(error) },
      headers: cors,
    };
  }
}

app.http('campsite-image', {
  methods: ['GET', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'campsite-image',
  handler: campsiteImageHandler,
});
