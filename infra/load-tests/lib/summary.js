function safeName() {
  const raw = (__ENV.K6_SCRIPT_NAME || 'k6-summary').replace(/[^a-zA-Z0-9._-]/g, '-');
  return raw.endsWith('.js') ? raw.slice(0, -3) : raw;
}

function resultDir() {
  return __ENV.RESULTS_DIR || 'infra/load-tests/results';
}

function textSummary(data) {
  const metrics = data.metrics || {};
  const duration = metrics.http_req_duration || {};
  const durationValues = duration.values || {};
  const failed = metrics.http_req_failed || {};
  const failedValues = failed.values || {};
  const reqs = metrics.http_reqs || {};
  const reqValues = reqs.values || {};
  const lines = [
    `script=${safeName()}`,
    `base_url=${__ENV.BASE_URL || 'http://localhost:8080'}`,
    `http_reqs=${reqValues.count || 0}`,
    `http_req_failed=${typeof failedValues.rate === 'number' ? failedValues.rate : 'n/a'}`,
    `http_req_duration_p95=${typeof durationValues['p(95)'] === 'number' ? durationValues['p(95)'] : 'n/a'}`,
    `http_req_duration_p99=${typeof durationValues['p(99)'] === 'number' ? durationValues['p(99)'] : 'n/a'}`,
    '',
    'Notas:',
    '- k6 puede escribir archivos desde handleSummary cuando el directorio existe.',
    '- Si el runtime no permite escritura, redirige stdout o usa --summary-export.',
  ];
  return `${lines.join('\n')}\n`;
}

export function handleSummary(data) {
  const base = `${resultDir()}/${safeName()}-${Date.now()}`;
  return {
    stdout: textSummary(data),
    [`${base}.json`]: JSON.stringify(data, null, 2),
    [`${base}.txt`]: textSummary(data),
  };
}
