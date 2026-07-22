/**
 * Cleenzo Traffic Simulation Test
 * Simulates 100 real customers using the app simultaneously
 * Run with: node traffic_test.js
 */

const SUPABASE_URL = 'https://hxrqgqhlbdconvgmmhgu.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh4cnFncWhsYmRjb252Z21taGd1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2ODIwMjQsImV4cCI6MjA5NTI1ODAyNH0.mHaAtk4e_vPysJ-6MBdYgZNirgp8bj3iabwkDmjxfFw';

const headers = {
  'Content-Type': 'application/json',
  'apikey': SUPABASE_KEY,
  'Authorization': `Bearer ${SUPABASE_KEY}`,
};

// ── Metrics tracker ───────────────────────────────────────────
const metrics = {
  totalRequests: 0,
  passed: 0,
  failed: 0,
  times: [],
  errors: [],
  phases: {},
};

function recordResult(phase, ms, success, error = null) {
  metrics.totalRequests++;
  metrics.times.push(ms);
  if (success) {
    metrics.passed++;
  } else {
    metrics.failed++;
    if (error) metrics.errors.push({ phase, error });
  }
  if (!metrics.phases[phase]) {
    metrics.phases[phase] = { passed: 0, failed: 0, times: [] };
  }
  metrics.phases[phase].times.push(ms);
  if (success) metrics.phases[phase].passed++;
  else metrics.phases[phase].failed++;
}

function avg(arr) {
  return arr.length ? Math.round(arr.reduce((a, b) => a + b, 0) / arr.length) : 0;
}

function progressBar(passed, total) {
  const pct = Math.round((passed / total) * 20);
  return `[${'█'.repeat(pct)}${'░'.repeat(20 - pct)}] ${passed}/${total}`;
}

// ── Simulate one customer's full app session ──────────────────
async function simulateCustomer(customerId) {
  const sessionResults = [];

  // Action 1: Open app → load services (like splash screen)
  let start = Date.now();
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/services?select=id,name,base_price,original_price,price_30min,price_60min,price_90min,duration_minutes,image_url&is_active=eq.true`,
      { headers }
    );
    const data = await res.json();
    const ms = Date.now() - start;
    const ok = res.ok && Array.isArray(data) && data.length > 0;
    recordResult('Load Services Screen', ms, ok);
    sessionResults.push({ action: 'Load services', ms, ok });
  } catch (e) {
    recordResult('Load Services Screen', Date.now() - start, false, e.message);
  }

  // Small delay between actions (realistic user behavior)
  await new Promise(r => setTimeout(r, Math.random() * 100));

  // Action 2: Open a service detail
  start = Date.now();
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/services?select=*&name=eq.Bathroom Cleaning`,
      { headers }
    );
    const ms = Date.now() - start;
    recordResult('Open Service Detail', ms, res.ok);
  } catch (e) {
    recordResult('Open Service Detail', Date.now() - start, false, e.message);
  }

  await new Promise(r => setTimeout(r, Math.random() * 100));

  // Action 3: Load reviews for service
  start = Date.now();
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/reviews?select=id,stars,text&limit=10`,
      { headers }
    );
    const ms = Date.now() - start;
    recordResult('Load Reviews', ms, res.ok);
  } catch (e) {
    recordResult('Load Reviews', Date.now() - start, false, e.message);
  }

  await new Promise(r => setTimeout(r, Math.random() * 100));

  // Action 4: Check available promo codes
  start = Date.now();
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/promo_codes?select=id,code,discount_type,discount_value&is_active=eq.true`,
      { headers }
    );
    const ms = Date.now() - start;
    recordResult('Check Promo Codes', ms, res.ok);
  } catch (e) {
    recordResult('Check Promo Codes', Date.now() - start, false, e.message);
  }

  await new Promise(r => setTimeout(r, Math.random() * 100));

  // Action 5: Load bookings screen
  start = Date.now();
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/bookings?select=id,status,final_amount,scheduled_at&limit=10`,
      { headers }
    );
    const ms = Date.now() - start;
    recordResult('Load Bookings Screen', ms, res.ok);
  } catch (e) {
    recordResult('Load Bookings Screen', Date.now() - start, false, e.message);
  }

  await new Promise(r => setTimeout(r, Math.random() * 100));

  // Action 6: Check worker availability (happens during booking flow)
  start = Date.now();
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/workers?select=user_id,is_available,schedule&is_available=eq.true`,
      { headers }
    );
    const ms = Date.now() - start;
    recordResult('Check Worker Availability', ms, res.ok);
  } catch (e) {
    recordResult('Check Worker Availability', Date.now() - start, false, e.message);
  }

  return sessionResults;
}

// ── Phase runner ──────────────────────────────────────────────
async function runPhase(label, count, fn) {
  console.log(`\n⚡ ${label} (${count} simultaneous users)`);
  const start = Date.now();
  const promises = Array(count).fill(null).map((_, i) => fn(i));
  await Promise.allSettled(promises);
  const total = Date.now() - start;
  console.log(`   ⏱  Phase completed in ${total}ms`);
  return total;
}

// ── Main ──────────────────────────────────────────────────────
async function main() {
  console.log('\n🚦 CLEENZO TRAFFIC SIMULATION TEST');
  console.log('   Simulating real customer app sessions\n');
  console.log('='.repeat(55));

  // Phase 1: 10 customers (light traffic)
  await runPhase('LIGHT TRAFFIC', 10, simulateCustomer);

  // Phase 2: 25 customers (normal traffic)  
  await runPhase('NORMAL TRAFFIC', 25, simulateCustomer);

  // Phase 3: 50 customers (busy period)
  await runPhase('BUSY PERIOD', 50, simulateCustomer);

  // Phase 4: 100 customers (peak traffic - morning rush)
  await runPhase('PEAK TRAFFIC — 100 CUSTOMERS', 100, simulateCustomer);

  // Phase 5: Spike test — sudden burst
  console.log('\n⚡ SPIKE TEST — sudden burst of 100 users in 1 second');
  const spikeStart = Date.now();
  await Promise.allSettled(
    Array(100).fill(null).map((_, i) => 
      fetch(
        `${SUPABASE_URL}/rest/v1/services?select=id,name,base_price&is_active=eq.true`,
        { headers }
      ).then(r => {
        const ms = Date.now() - spikeStart;
        recordResult('Spike Test', ms, r.ok);
      }).catch(e => recordResult('Spike Test', Date.now() - spikeStart, false, e.message))
    )
  );
  console.log(`   ⏱  Spike completed in ${Date.now() - spikeStart}ms`);

  // ── Final Report ──────────────────────────────────────────
  console.log('\n' + '='.repeat(55));
  console.log('📊 TRAFFIC TEST REPORT\n');

  const totalTime = metrics.times.reduce((a, b) => a + b, 0);
  const avgTime = avg(metrics.times);
  const maxTime = Math.max(...metrics.times);
  const minTime = Math.min(...metrics.times);
  const successRate = Math.round((metrics.passed / metrics.totalRequests) * 100);

  console.log(`📈 Total Requests:    ${metrics.totalRequests}`);
  console.log(`✅ Successful:        ${metrics.passed} (${successRate}%)`);
  console.log(`❌ Failed:            ${metrics.failed}`);
  console.log(`⚡ Avg Response:      ${avgTime}ms`);
  console.log(`🐢 Slowest:           ${maxTime}ms`);
  console.log(`🚀 Fastest:           ${minTime}ms`);

  // Per-action breakdown
  console.log('\n📱 PER ACTION BREAKDOWN:\n');
  Object.entries(metrics.phases).forEach(([phase, data]) => {
    const phaseAvg = avg(data.times);
    const phaseMax = Math.max(...data.times);
    const phaseSuccess = Math.round((data.passed / (data.passed + data.failed)) * 100);
    const status = phaseSuccess === 100 ? '✅' : phaseSuccess >= 90 ? '🟡' : '❌';
    console.log(`${status} ${phase}`);
    console.log(`   Success: ${phaseSuccess}% | Avg: ${phaseAvg}ms | Max: ${phaseMax}ms`);
  });

  // Overall verdict
  console.log('\n🏆 VERDICT:\n');
  if (successRate === 100 && avgTime < 300) {
    console.log('   🟢 PRODUCTION READY');
    console.log('   Your app handles 100 concurrent users perfectly.');
    console.log('   Response times are well within acceptable limits.');
  } else if (successRate >= 95 && avgTime < 500) {
    console.log('   🟡 MOSTLY READY');
    console.log('   Minor issues under extreme load but acceptable for launch.');
  } else if (successRate >= 90) {
    console.log('   🟠 NEEDS OPTIMIZATION');
    console.log('   Some failures under heavy load. Consider Supabase plan upgrade.');
  } else {
    console.log('   🔴 NOT READY FOR PRODUCTION');
    console.log('   Too many failures under load. Check Supabase limits and RLS policies.');
  }

  if (metrics.errors.length > 0) {
    console.log('\n❌ ERRORS FOUND:');
    const unique = [...new Set(metrics.errors.map(e => e.error))];
    unique.forEach(e => console.log(`   • ${e}`));
  }

  console.log('\n' + '='.repeat(55));
  console.log('✅ Traffic simulation complete!\n');
}

main().catch(console.error);