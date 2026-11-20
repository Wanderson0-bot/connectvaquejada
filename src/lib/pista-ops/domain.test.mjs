import assert from "node:assert/strict";
import test from "node:test";
import {
  assertEntryEligible,
  authorizePista,
  beginNextRound,
  callNext,
  callNextIdempotently,
  correctResult,
  createPendingRuns,
  enqueueRaboDaGata,
  initialQueue,
  markReturnInterrupted,
  planRound,
  recordRunResult,
  recordTie,
  realizeReturn,
  savePrizeVersion,
  startRound,
} from "./domain.ts";

const pendingRuns = () => createPendingRuns(2).value;
const entry = (id, passwordNumber, createdAt = "2026-01-01T00:00:00Z", paymentStatus = "pago") => ({
  id,
  passwordNumber,
  createdAt,
  paymentStatus,
  runs: pendingRuns(),
});
const item = (entryId, runIndex = 0, kind = "regular") => ({ entryId, runIndex, kind });

test("each enrollment has exactly two regular runs", () => {
  assert.equal(createPendingRuns(2).value.length, 2);
  assert.equal(createPendingRuns(1).error.code, "TWO_RUNS_REQUIRED");
  assert.equal(createPendingRuns(3).error.code, "TWO_RUNS_REQUIRED");
});

test("zero is zero and Valeu Boi requires a finite score", () => {
  const running = { status: "running", returnsPerformed: 0 };
  assert.deepEqual(recordRunResult(running, { status: "zero" }).value, {
    status: "zero",
    score: 0,
    returnsPerformed: 0,
  });
  assert.equal(recordRunResult(running, { status: "valeu_boi", score: 0 }).value.score, 0);
  assert.equal(recordRunResult(running, { status: "valeu_boi", score: NaN }).error.code, "SCORE_REQUIRED");
  assert.equal(recordRunResult({ status: "pending", returnsPerformed: 0 }, { status: "zero" }).error.code, "RUN_NOT_PENDING");
});

test("initial queue sorts by password and created time, waiting for the first result before a second run", () => {
  const returning = { ...entry("returning", 1), runs: [{ status: "return_pending", returnsPerformed: 0 }, pendingRuns()[1]] };
  const queue = initialQueue([
    entry("later", 2),
    entry("tie-new", 1, "2026-01-02T00:00:00Z"),
    entry("tie-old", 1, "2026-01-01T00:00:00Z"),
    { ...entry("cancelled", 3, undefined, "cancelado") },
    returning,
  ]);
  assert.deepEqual(queue.value.map((queued) => `${queued.entryId}:${queued.runIndex}`), [
    "tie-old:0",
    "tie-new:0",
    "later:0",
  ]);
});

test("canceled registration is rejected for operational inclusion", () => {
  assert.equal(assertEntryEligible(entry("cancelled", 1, undefined, "cancelado")).error.code, "CANCELLED_ENTRY");
});

test("an interrupted return releases its position without consuming a bull", () => {
  const planned = planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 2 }).value;
  const active = startRound(planned, []).value;
  const occupied = { ...active, positions: [item("entry-1"), null] };
  const interrupted = markReturnInterrupted(occupied, { status: "running", returnsPerformed: 0 }, 0).value;
  assert.deepEqual(interrupted.round.positions, [null, null]);
  assert.equal(interrupted.round.consumedBulls, 0);
  assert.equal(interrupted.run.status, "return_pending");
  assert.equal(interrupted.round.returnQueue.length, 1);
});

test("a run that already realized a return cannot enter return pending again", () => {
  const planned = planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 2 }).value;
  const active = startRound(planned, []).value;
  const occupied = { ...active, positions: [item("entry-1"), null] };
  const alreadyReturned = { status: "running", returnsPerformed: 1 };
  const roundBefore = structuredClone(occupied);
  const runBefore = structuredClone(alreadyReturned);
  const result = markReturnInterrupted(occupied, alreadyReturned, 0);
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.error.code, "RETORNO_JA_REALIZADO");
  assert.deepEqual(occupied, roundBefore);
  assert.deepEqual(alreadyReturned, runBefore);
});

test("realizing a return consumes exactly one bull and uses one free position", () => {
  const planned = planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 2 }).value;
  const active = startRound(planned, []).value;
  const queued = { ...active, returnQueue: [item("entry-1")] };
  const realized = realizeReturn(queued, { status: "return_pending", returnsPerformed: 0 }, item("entry-1")).value;
  assert.equal(realized.round.consumedBulls, 1);
  assert.equal(realized.round.positions.filter(Boolean).length, 1);
  assert.equal(realized.round.returnQueue.length, 0);
  assert.deepEqual(realized.run, { status: "running", returnsPerformed: 1 });
});

test("pending returns do not block the regular queue", () => {
  const planned = planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 2 }).value;
  const active = startRound(planned, [item("regular-1"), item("regular-2")]).value;
  const withReturn = { ...active, returnQueue: [item("return-1")] };
  const call = callNext(withReturn).value;
  assert.equal(call.called.entryId, "regular-1");
  assert.equal(call.round.returnQueue.length, 1);
});

test("Rabo da Gata joins the queue tail without reserving a position", () => {
  const planned = planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 2 }).value;
  const active = startRound(planned, [item("regular-1")]).value;
  const forwarded = enqueueRaboDaGata(active, item("rabo", 0, "rabo_da_gata")).value;
  assert.deepEqual(forwarded.queue.map((queued) => queued.entryId), ["regular-1", "rabo"]);
  assert.equal(forwarded.positions.every((position) => position === null), true);
  const called = callNext(forwarded).value;
  assert.equal(called.called.entryId, "regular-1");
  assert.equal(called.round.positions.filter(Boolean).length, 1);
});

test("Rabo da Gata waits for the next round when no position is free", () => {
  const planned = planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 1 }).value;
  const active = startRound(planned, []).value;
  const full = { ...active, positions: [item("called")] };
  const forwarded = enqueueRaboDaGata(full, item("rabo", 0, "rabo_da_gata")).value;
  assert.equal(forwarded.queue.length, 0);
  assert.equal(forwarded.waitingNextRound[0].entryId, "rabo");
  assert.equal(forwarded.positions[0].entryId, "called");
});

test("bull counts vary and rounds are independent by event and category", () => {
  const twoBulls = planRound({ eventId: "event-1", categoryId: "cat-a", number: 1, bulls: 2 }).value;
  const sevenBulls = planRound({ eventId: "event-1", categoryId: "cat-b", number: 4, bulls: 7 }).value;
  assert.equal(twoBulls.positions.length, 2);
  assert.equal(sevenBulls.positions.length, 7);
  assert.equal(sevenBulls.number, 4);
  assert.equal(beginNextRound(twoBulls, { ...sevenBulls, categoryId: "cat-a" }, item("entry")).ok, true);
  assert.equal(beginNextRound(twoBulls, sevenBulls, item("entry")).error.code, "ROUND_SCOPE_MISMATCH");
});

test("missing next round preserves an explicit waiting state", () => {
  const active = startRound(planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 1 }).value, []).value;
  const outcome = beginNextRound(active, null, item("entry")).value;
  assert.equal(outcome.state, "awaiting_next_round");
  assert.equal(outcome.round.status, "awaiting_next_round");
  assert.equal(outcome.round.waitingNextRound[0].entryId, "entry");
});

test("result correction appends an immutable audit record", () => {
  const history = [];
  const input = { status: "valeu_boi", score: 8 };
  const corrected = correctResult(input, { status: "zero", score: 0 }, history, {
    authorId: "user-1",
    at: "2026-01-01T10:00:00Z",
    reason: "Revisão do juiz",
  }).value;
  assert.deepEqual(input, { status: "valeu_boi", score: 8 });
  assert.equal(corrected.current.status, "zero");
  assert.deepEqual(corrected.history[0].previous, { status: "valeu_boi", score: 8 });
  assert.equal(history.length, 0);
});

test("saving prizes creates increasing versions without deleting earlier ones", () => {
  const original = [{ version: 1, places: [{ place: 1, amount: 100 }] }];
  const saved = savePrizeVersion(original, [{ place: 1, amount: 120 }, { place: 5, amount: 20 }]).value;
  assert.equal(saved.length, 2);
  assert.equal(saved[1].version, 2);
  assert.equal(original.length, 1);
});

test("ties preserve entered decision and terms without assuming champion or split", () => {
  const tie = recordTie({ participantIds: ["a", "b"], decision: "Desempate posterior", terms: "Nova passada" }).value;
  assert.equal(tie.decision, "Desempate posterior");
  assert.equal(tie.terms, "Nova passada");
  assert.equal(tie.championId, null);
  assert.equal(tie.prizeDivision, null);
});

test("invalid inputs return stable errors and do not mutate inputs", () => {
  const original = entry("invalid", 0);
  const snapshot = structuredClone(original);
  assert.equal(initialQueue([original]).error.code, "INVALID_INPUT");
  assert.deepEqual(original, snapshot);
  assert.equal(planRound({ eventId: "event", categoryId: "cat", number: 1, bulls: 0 }).error.code, "INVALID_INPUT");
});

test("authorization requires identity, profile, same park, and event role", () => {
  const authorized = {
    authenticatedUserId: "user-1",
    profileUserId: "user-1",
    profileParkId: "park-1",
    eventParkId: "park-1",
    activeRole: "locutor",
    allowedRoles: ["organizador", "locutor"],
  };
  assert.equal(authorizePista(authorized).ok, true);
  assert.equal(authorizePista({ ...authorized, profileUserId: null }).error.code, "FORBIDDEN");
  assert.equal(authorizePista({ ...authorized, profileParkId: "park-2" }).error.code, "FORBIDDEN");
  assert.equal(authorizePista({ ...authorized, activeRole: "admin" }).error.code, "FORBIDDEN");
});

test("existing rounds cannot be reordered or canceled after start", () => {
  const active = startRound(planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 1 }).value, []).value;
  assert.equal(startRound(active, []).error.code, "ROUND_ALREADY_STARTED");
});

test("the same call request returns the original call without advancing twice", () => {
  const active = startRound(planRound({ eventId: "event-1", categoryId: "cat-1", number: 1, bulls: 3 }).value, [item("first"), item("second")]).value;
  const first = callNextIdempotently(active, "request-1", []).value;
  const repeated = callNextIdempotently(active, "request-1", first.requests).value;
  assert.equal(first.called.entryId, "first");
  assert.equal(repeated.called.entryId, "first");
  assert.equal(repeated.round.queue.length, 1);
  assert.equal(repeated.round.positions.filter(Boolean).length, 1);
  assert.equal(repeated.requests.length, 1);
});
