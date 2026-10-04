const assert = require('node:assert/strict');
const { validateCompletion } = require('./stress-completion');
const proof = { valid: true, timeout: false, requested_s: 90, combat_s: 90, physics_hz: 60, observation_frames: 5400,
 rounds: [{ round: 1, effective_ticks: 2700, combat_s: 45 }, { round: 2, effective_ticks: 2700, combat_s: 45 }] };
assert(validateCompletion(proof, 90));
for (const broken of [null, { ...proof, valid: false }, { ...proof, timeout: true },
 { ...proof, combat_s: 89.99 }, { ...proof, rounds: proof.rounds.slice(0, 1) },
 { ...proof, requested_s: 45 }, { ...proof, observation_frames: 0 },
 { ...proof, rounds: [{ round: 1, effective_ticks: 0, combat_s: 90 }] },
 { ...proof, rounds: [{ round: 1, effective_ticks: 1, combat_s: 90 }] }]) {
 assert(!validateCompletion(broken, 90));
}
console.log('PASS stress completion rejects missing, short, interrupted and inconsistent evidence (10 checks)');
