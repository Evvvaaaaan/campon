import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';

import { searchCampsiteReservation } from './_campsite_reservation.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

export async function campsiteReservationHandler(
  request: HttpRequest,
  _context: InvocationContext,
): Promise<HttpResponseInit> {
  if (request.method === 'OPTIONS') return { status: 204, headers: cors };
  const name = request.query.get('name') ?? '';
  if (!name.trim()) {
    return {
      status: 400,
      jsonBody: { reservation: null, error: 'name is required' },
      headers: cors,
    };
  }
  try {
    const result = await searchCampsiteReservation(name);
    return { status: 200, jsonBody: result, headers: cors };
  } catch (error) {
    return {
      status: 502,
      jsonBody: { reservation: null, error: String(error) },
      headers: cors,
    };
  }
}

app.http('campsite-reservation', {
  methods: ['GET', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'campsite-reservation',
  handler: campsiteReservationHandler,
});
