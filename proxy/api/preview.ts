import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';

import { generatePreview } from './_handler.ts';
import type { PreviewRequest } from './_preview_core.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export async function previewHandler(
  request: HttpRequest,
  _context: InvocationContext,
): Promise<HttpResponseInit> {
  if (request.method === 'OPTIONS') return { status: 204, headers: cors };
  try {
    const body = (await request.json()) as PreviewRequest;
    const result = await generatePreview(body);
    return { status: 200, jsonBody: result, headers: cors };
  } catch (e) {
    return { status: 200, jsonBody: { preview: null, error: String(e) }, headers: cors };
  }
}

app.http('preview', {
  methods: ['POST', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'preview',
  handler: previewHandler,
});
