import { app, type InvocationContext } from '@azure/functions';

// Consumption 플랜은 유휴 시 콜드스타트가 걸린다. 5분마다 워커를 깨워둬서
// 실제 /api/plan, /api/preview 요청이 콜드스타트를 맞을 확률을 줄인다.
export async function warmupHandler(_myTimer: unknown, context: InvocationContext): Promise<void> {
  context.log('[warmup] keep-alive tick');
}

app.timer('warmup', {
  schedule: '0 */5 * * * *',
  handler: warmupHandler,
});
