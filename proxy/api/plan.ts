import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';

import { generatePlan } from './_handler.ts';
import type { PlanRequest } from './_plan_core.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export async function planHandler(
  request: HttpRequest,
  _context: InvocationContext,
): Promise<HttpResponseInit> {
  if (request.method === 'OPTIONS') return { status: 204, headers: cors };
  try {
    const body = (await request.json()) as PlanRequest;
    const result = await generatePlan(body);
    return { status: 200, jsonBody: result, headers: cors };
  } catch (e) {
    return { status: 200, jsonBody: { plan: null, error: String(e) }, headers: cors };
  }
}

app.http('plan', {
  methods: ['POST', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'plan',
  handler: planHandler,
});
