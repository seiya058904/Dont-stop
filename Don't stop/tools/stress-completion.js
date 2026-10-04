'use strict';

// A summary (including its rounded duration) is never completion evidence.
function validateCompletion(proof, requested) {
 if (!proof || proof.valid !== true || proof.timeout || !Number.isFinite(requested) || requested <= 0 || proof.requested_s !== requested) return false;
 if (!Number.isFinite(proof.combat_s) || proof.combat_s < requested || !(proof.observation_frames > 0) || !Array.isArray(proof.rounds) || !proof.rounds.length) return false;
 if (!Number.isInteger(proof.physics_hz) || proof.physics_hz <= 0) return false;
 let seconds = 0;
 for (const [i, round] of proof.rounds.entries()) {
  if (round.round !== i + 1 || !Number.isInteger(round.effective_ticks) || round.effective_ticks <= 0 || !Number.isFinite(round.combat_s) || round.combat_s <= 0) return false;
  if (Math.abs(round.combat_s - round.effective_ticks / proof.physics_hz) > 0.001) return false;
  seconds += round.combat_s;
 }
 return Math.abs(seconds - proof.combat_s) < 0.001 && seconds >= requested;
}
module.exports = { validateCompletion };
