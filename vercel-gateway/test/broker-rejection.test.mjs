import assert from 'node:assert/strict';
import test from 'node:test';
import { brokerRejection } from '../api/index.mjs';

test('reports the broker enum, operation and stage without private upstream data', () => {
  const rejection = brokerRejection({
    stage: 'symbols', brokerCode: 'ACCOUNT_NOT_AUTHORIZED', operation: 2102,
    description: 'private broker data',
  });
  assert.deepEqual(JSON.parse(JSON.stringify(rejection)), {
    error: 'ctrader_broker_rejected_request', stage: 'symbols',
    brokerCode: 'ACCOUNT_NOT_AUTHORIZED', operation: 2102,
  });
});

test('does not reflect unrecognized broker data', () => {
  const rejection = brokerRejection({ stage: 'private', brokerCode: 'PRIVATE_IDENTIFIER', operation: 123456 });
  assert.deepEqual(JSON.parse(JSON.stringify(rejection)), {
    error: 'ctrader_broker_rejected_request', stage: 'other',
  });
});
