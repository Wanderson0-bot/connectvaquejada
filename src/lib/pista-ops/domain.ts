export type RuleErrorCode =
  | "INVALID_INPUT"
  | "TWO_RUNS_REQUIRED"
  | "CANCELLED_ENTRY"
  | "RUN_NOT_PENDING"
  | "RETORNO_JA_REALIZADO"
  | "SCORE_REQUIRED"
  | "NO_POSITION"
  | "NO_NEXT_ROUND"
  | "ROUND_NOT_PLANNED"
  | "ROUND_ALREADY_STARTED"
  | "ROUND_SCOPE_MISMATCH"
  | "DUPLICATE_CALL"
  | "RESULT_NOT_CORRECTABLE"
  | "CORRECTION_REASON_REQUIRED"
  | "PRIZE_INVALID"
  | "TIE_TERMS_REQUIRED"
  | "FORBIDDEN";

export type RuleResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: { code: RuleErrorCode } };

export type RegularRun =
  | { status: "pending"; returnsPerformed: 0 }
  | { status: "return_pending"; returnsPerformed: 0 }
  | { status: "running"; returnsPerformed: 0 | 1 }
  | { status: "zero"; score: 0; returnsPerformed: 0 | 1 }
  | { status: "valeu_boi"; score: number; returnsPerformed: 0 | 1 }
  | { status: "sem_direito"; returnsPerformed: 0 };

export type Entry = {
  id: string;
  passwordNumber: number;
  createdAt: string;
  paymentStatus: string;
  runs: readonly RegularRun[];
};

export type QueueItem = {
  entryId: string;
  runIndex: 0 | 1;
  kind: "regular" | "rabo_da_gata";
};

export type Round = {
  eventId: string;
  categoryId: string;
  number: number;
  bulls: number;
  consumedBulls: number;
  status: "planned" | "active" | "finished" | "awaiting_next_round";
  queue: readonly QueueItem[];
  returnQueue: readonly QueueItem[];
  positions: readonly (QueueItem | null)[];
  waitingNextRound: readonly QueueItem[];
};

export type ResultHistoryItem = {
  previous: { status: "zero" | "valeu_boi"; score: number };
  next: { status: "zero" | "valeu_boi"; score: number };
  authorId: string;
  at: string;
  reason: string;
};

function failure<T>(code: RuleErrorCode): RuleResult<T> {
  return { ok: false, error: { code } };
}

function success<T>(value: T): RuleResult<T> {
  return { ok: true, value };
}

function validScore(score: number): boolean {
  return Number.isFinite(score) && score >= 0;
}

export function createPendingRuns(count: number): RuleResult<readonly RegularRun[]> {
  if (!Number.isSafeInteger(count) || count !== 2) {
    return failure("TWO_RUNS_REQUIRED");
  }
  return success([
    { status: "pending", returnsPerformed: 0 },
    { status: "pending", returnsPerformed: 0 },
  ]);
}

export function validateEntry(entry: Entry): RuleResult<Entry> {
  if (
    !entry ||
    typeof entry.id !== "string" ||
    !entry.id ||
    !Number.isSafeInteger(entry.passwordNumber) ||
    entry.passwordNumber < 1 ||
    !Number.isFinite(Date.parse(entry.createdAt)) ||
    !Array.isArray(entry.runs)
  ) {
    return failure("INVALID_INPUT");
  }
  if (entry.runs.length !== 2) return failure("TWO_RUNS_REQUIRED");
  return success({ ...entry, runs: entry.runs.map((run) => ({ ...run })) });
}

export function assertEntryEligible(entry: Entry): RuleResult<Entry> {
  const checked = validateEntry(entry);
  if (!checked.ok) return checked;
  if (entry.paymentStatus === "cancelado") return failure("CANCELLED_ENTRY");
  return checked;
}

export function initialQueue(entries: readonly Entry[]): RuleResult<readonly QueueItem[]> {
  if (!Array.isArray(entries)) return failure("INVALID_INPUT");
  const eligible: Entry[] = [];
  for (const entry of entries) {
    const checked = validateEntry(entry);
    if (!checked.ok) return checked;
    if (entry.paymentStatus === "cancelado") continue;
    eligible.push(checked.value);
  }
  eligible.sort(
    (left, right) =>
      left.passwordNumber - right.passwordNumber ||
      Date.parse(left.createdAt) - Date.parse(right.createdAt) ||
      left.id.localeCompare(right.id),
  );
  return success(
    eligible.flatMap((entry) =>
      entry.runs.flatMap((run, index) =>
        run.status === "pending" && (index === 0 || entry.runs[0].status === "valeu_boi")
          ? [{ entryId: entry.id, runIndex: index as 0 | 1, kind: "regular" as const }]
          : [],
      ),
    ),
  );
}

export function recordRunResult(
  run: RegularRun,
  result: { status: "zero" } | { status: "valeu_boi"; score: number },
): RuleResult<RegularRun> {
  if (!run || run.status !== "running") return failure("RUN_NOT_PENDING");
  if (result.status === "zero") {
    return success({ status: "zero", score: 0, returnsPerformed: run.returnsPerformed });
  }
  if (!validScore(result.score)) return failure("SCORE_REQUIRED");
  return success({ status: "valeu_boi", score: result.score, returnsPerformed: run.returnsPerformed });
}

export function markReturnInterrupted(
  round: Round,
  run: RegularRun,
  positionIndex: number,
): RuleResult<{ round: Round; run: RegularRun }> {
  if (run.status === "running" && run.returnsPerformed === 1) {
    return failure("RETORNO_JA_REALIZADO");
  }
  const position = round.positions[positionIndex];
  if (
    round.status !== "active" ||
    run.status !== "running" ||
    !Number.isSafeInteger(positionIndex) ||
    !position
  ) {
    return failure("INVALID_INPUT");
  }
  const positions = round.positions.map((item, index) => (index === positionIndex ? null : item));
  const returnItem = { ...position };
  return success({
    round: { ...round, positions, returnQueue: [...round.returnQueue, returnItem] },
    run: { status: "return_pending", returnsPerformed: 0 },
  });
}

export function realizeReturn(
  round: Round,
  run: RegularRun,
  item: QueueItem,
): RuleResult<{ round: Round; run: RegularRun }> {
  if (run.status !== "return_pending") return failure("RUN_NOT_PENDING");
  if (round.status === "awaiting_next_round") return failure("NO_NEXT_ROUND");
  if (round.status !== "active") return failure("ROUND_NOT_PLANNED");
  if (!item.entryId || !round.returnQueue.some(
    (queued) => queued.entryId === item.entryId && queued.runIndex === item.runIndex,
  )) {
    return failure("INVALID_INPUT");
  }
  if (round.consumedBulls >= round.bulls) {
    return failure("NO_POSITION");
  }
  const freePosition = round.positions.findIndex((position) => position === null);
  if (freePosition < 0) return failure("NO_POSITION");
  const positions = round.positions.map((position, index) =>
    index === freePosition ? { ...item, kind: "regular" as const } : position,
  );
  const returnQueue = round.returnQueue.filter(
    (queued) => queued.entryId !== item.entryId || queued.runIndex !== item.runIndex,
  );
  return success({
    round: { ...round, positions, returnQueue, consumedBulls: round.consumedBulls + 1 },
    run: { status: "running", returnsPerformed: 1 },
  });
}

export function planRound(input: {
  eventId: string;
  categoryId: string;
  number: number;
  bulls: number;
}): RuleResult<Round> {
  if (
    !input.eventId ||
    !input.categoryId ||
    !Number.isSafeInteger(input.number) ||
    input.number < 1 ||
    !Number.isSafeInteger(input.bulls) ||
    input.bulls < 1
  ) {
    return failure("INVALID_INPUT");
  }
  return success({
    eventId: input.eventId,
    categoryId: input.categoryId,
    number: input.number,
    bulls: input.bulls,
    consumedBulls: 0,
    status: "planned",
    queue: [],
    returnQueue: [],
    positions: Array.from({ length: input.bulls }, () => null),
    waitingNextRound: [],
  });
}

export function startRound(round: Round, queue: readonly QueueItem[]): RuleResult<Round> {
  if (round.status !== "planned") return failure("ROUND_ALREADY_STARTED");
  const unique = new Set(queue.map((item) => `${item.entryId}:${item.runIndex}:${item.kind}`));
  if (unique.size !== queue.length) return failure("DUPLICATE_CALL");
  return success({ ...round, status: "active", queue: queue.map((item) => ({ ...item })) });
}

export function callNext(round: Round): RuleResult<{ round: Round; called: QueueItem | null }> {
  if (round.status !== "active") return failure("ROUND_NOT_PLANNED");
  const availablePositions = round.positions.filter((position) => position === null).length;
  if (round.queue.length === 0) {
    const next = { ...round, status: "awaiting_next_round" as const };
    return success({ round: next, called: null });
  }
  if (availablePositions === 0) return failure("NO_POSITION");
  const [called, ...queue] = round.queue;
  const positionIndex = round.positions.findIndex((position) => position === null);
  const positions = round.positions.map((position, index) => (index === positionIndex ? { ...called } : position));
  return success({ round: { ...round, queue, positions }, called: { ...called } });
}

export type CallRequestRecord = {
  key: string;
  eventId: string;
  categoryId: string;
  roundNumber: number;
  outcome: { round: Round; called: QueueItem | null };
};

export function callNextIdempotently(
  round: Round,
  requestKey: string,
  previousRequests: readonly CallRequestRecord[],
): RuleResult<{ round: Round; called: QueueItem | null; requests: readonly CallRequestRecord[] }> {
  if (!requestKey.trim()) return failure("INVALID_INPUT");
  const previous = previousRequests.find(
    (request) => request.key === requestKey && request.eventId === round.eventId &&
      request.categoryId === round.categoryId && request.roundNumber === round.number,
  );
  if (previous) {
    return success({
      round: { ...previous.outcome.round, queue: [...previous.outcome.round.queue], positions: [...previous.outcome.round.positions] },
      called: previous.outcome.called ? { ...previous.outcome.called } : null,
      requests: [...previousRequests],
    });
  }
  const next = callNext(round);
  if (!next.ok) return next;
  const record: CallRequestRecord = {
    key: requestKey,
    eventId: round.eventId,
    categoryId: round.categoryId,
    roundNumber: round.number,
    outcome: { round: next.value.round, called: next.value.called },
  };
  return success({ ...next.value, requests: [...previousRequests, record] });
}

export function releaseCall(round: Round, item: QueueItem, positionIndex: number): RuleResult<Round> {
  const position = round.positions[positionIndex];
  if (!position || position.entryId !== item.entryId || position.runIndex !== item.runIndex) {
    return failure("INVALID_INPUT");
  }
  const positions = round.positions.map((current, index) => (index === positionIndex ? null : current));
  return success({ ...round, positions, queue: [{ ...item }, ...round.queue] });
}

export function enqueueRaboDaGata(round: Round, item: QueueItem): RuleResult<Round> {
  if (round.status !== "active") return failure("ROUND_NOT_PLANNED");
  const duplicate = [...round.queue, ...round.waitingNextRound].some(
    (queued) => queued.entryId === item.entryId && queued.runIndex === item.runIndex,
  );
  if (duplicate) return failure("DUPLICATE_CALL");
  const hasFreePosition = round.positions.some((position) => position === null);
  const unassignedCapacity = round.bulls - round.consumedBulls;
  if (!hasFreePosition || unassignedCapacity <= 0) {
    return success({ ...round, waitingNextRound: [...round.waitingNextRound, { ...item, kind: "rabo_da_gata" }] });
  }
  return success({ ...round, queue: [...round.queue, { ...item, kind: "rabo_da_gata" }] });
}

export function beginNextRound(
  previous: Round,
  next: Round | null,
  item: QueueItem,
): RuleResult<{ round: Round | null; state: "queued" | "awaiting_next_round" }> {
  if (!next) {
    return success({
      round: { ...previous, waitingNextRound: [...previous.waitingNextRound, { ...item }], status: "awaiting_next_round" },
      state: "awaiting_next_round",
    });
  }
  if (previous.eventId !== next.eventId || previous.categoryId !== next.categoryId) {
    return failure("ROUND_SCOPE_MISMATCH");
  }
  if (next.status !== "planned") return failure("ROUND_ALREADY_STARTED");
  return success({ round: { ...next, queue: [...next.queue, { ...item }] }, state: "queued" });
}

export function correctResult(
  current: { status: string; score?: number },
  next: { status: "zero" | "valeu_boi"; score: number },
  history: readonly ResultHistoryItem[],
  metadata: { authorId: string; at: string; reason: string },
): RuleResult<{ current: ResultHistoryItem["next"]; history: readonly ResultHistoryItem[] }> {
  if (current.status !== "zero" && current.status !== "valeu_boi") return failure("RESULT_NOT_CORRECTABLE");
  if (!validScore(next.score) || (next.status === "zero" && next.score !== 0)) return failure("INVALID_INPUT");
  const reason = metadata.reason.trim();
  if (!metadata.authorId || !metadata.at || !reason) return failure("CORRECTION_REASON_REQUIRED");
  const item: ResultHistoryItem = {
    previous: { status: current.status, score: current.score ?? 0 },
    next: { ...next },
    authorId: metadata.authorId,
    at: metadata.at,
    reason,
  };
  return success({ current: { ...next }, history: [...history, item] });
}

export function savePrizeVersion(
  versions: readonly { version: number; places: readonly { place: number; amount: number }[] }[],
  places: readonly { place: number; amount: number }[],
): RuleResult<readonly { version: number; places: readonly { place: number; amount: number }[] }[]> {
  if (
    places.length === 0 ||
    places.some((item) => !Number.isSafeInteger(item.place) || item.place < 1 || !validScore(item.amount)) ||
    new Set(places.map((item) => item.place)).size !== places.length
  ) {
    return failure("PRIZE_INVALID");
  }
  const latest = versions.reduce((max, item) => Math.max(max, item.version), 0);
  return success([...versions, { version: latest + 1, places: places.map((item) => ({ ...item })) }]);
}

export function recordTie(input: {
  participantIds: readonly string[];
  decision: string;
  terms: string;
}): RuleResult<{ participantIds: readonly string[]; decision: string; terms: string; championId: null; prizeDivision: null }> {
  if (
    input.participantIds.length < 2 ||
    !input.decision.trim() ||
    !input.terms.trim()
  ) {
    return failure("TIE_TERMS_REQUIRED");
  }
  return success({
    participantIds: [...input.participantIds],
    decision: input.decision.trim(),
    terms: input.terms.trim(),
    championId: null,
    prizeDivision: null,
  });
}

export function authorizePista(input: {
  authenticatedUserId: string | null;
  profileUserId: string | null;
  profileParkId: string | null;
  eventParkId: string | null;
  activeRole: string | null;
  allowedRoles: readonly string[];
}): RuleResult<true> {
  if (
    !input.authenticatedUserId ||
    input.authenticatedUserId !== input.profileUserId ||
    !input.profileParkId ||
    input.profileParkId !== input.eventParkId ||
    !input.activeRole ||
    !input.allowedRoles.includes(input.activeRole)
  ) {
    return failure("FORBIDDEN");
  }
  return success(true);
}

export function refuseStartedRoundMutation(round: Round): RuleResult<never> {
  if (round.status !== "planned") return failure("ROUND_ALREADY_STARTED");
  return failure("INVALID_INPUT");
}
