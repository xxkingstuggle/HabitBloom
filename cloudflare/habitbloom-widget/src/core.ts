export interface StorageAdapter {
  get<T = unknown>(key: string): Promise<T | undefined>;
  put<T = unknown>(key: string, value: T): Promise<void>;
  delete(key: string | string[]): Promise<boolean | number>;
  list(options?: { prefix?: string }): Promise<Map<string, unknown>>;
}

export type HabitSnapshot = {
  id: string;
  name: string;
  icon: string;
  colorName: string;
  cardStyle?: string;
  streakDays: number;
  totalDays: number;
  completionRate?: number;
  isCompletedToday: boolean;
  imageFileName?: string | null;
  imageData?: string | null;
  updatedAt?: string;
};

export type WidgetSnapshot = {
  deviceKey: string;
  updatedAt: string;
  dayKey?: string | null;
  selectedHabitID?: string | null;
  habits: HabitSnapshot[];
};

export type CheckInRequest = {
  habitID: string;
  isCompletedToday: boolean;
  dayKey?: string | null;
  snapshot?: WidgetSnapshot | null;
};

export type ImageManifest = {
  files: string[];
};

export type BackupCheckIn = {
  id: string;
  day: string;
  isCompleted: boolean;
  note?: string;
  createdAt: string;
};

export type BackupHabit = {
  id: string;
  name: string;
  icon: string;
  colorName?: string;
  cardStyle?: string;
  targetWeekdayMask: number;
  reminderEnabled: boolean;
  reminderHour: number;
  reminderMinute: number;
  reminderWeekdayMask: number;
  sortOrder: number;
  createdAt: string;
  checkIns: BackupCheckIn[];
};

export type BackupArchive = {
  version: number;
  deviceKey: string;
  exportedAt: string;
  habits: BackupHabit[];
};

export type RouteAction =
  | "getSnapshot"
  | "putSnapshot"
  | "checkIn"
  | "getBackup"
  | "putBackup"
  | "putImage"
  | "getImage"
  | "getImages"
  | "putImages";

export type ParsedRoute = {
  action: RouteAction;
  deviceKey: string;
  imageFile?: string;
  requiresAuth: boolean;
};

export type RouteParseResult =
  | { ok: true; route: ParsedRoute }
  | { ok: false; status: number; error: string };

export const INTERNAL_ACTION_HEADER = "x-habitbloom-action";
export const INTERNAL_DEVICE_KEY_HEADER = "x-habitbloom-device-key";
export const INTERNAL_IMAGE_FILE_HEADER = "x-habitbloom-image-file";

const snapshotKey = "snapshot";
const backupKey = "backup";
const imageManifestKey = "image-manifest";
const imagePrefix = "image/";

export const MAX_JSON_BYTES = 2_000_000;
export const MAX_IMAGE_BYTES = 2_000_000;
const MAX_HABITS = 500;
const MAX_CHECKINS_PER_HABIT = 10_000;
const MAX_EMBEDDED_IMAGE_BASE64_LENGTH = 350_000;

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export function isValidDeviceKey(deviceKey: string): boolean {
  if (!/^[A-Za-z0-9._-]{4,128}$/.test(deviceKey)) {
    return false;
  }
  return !deviceKey.includes("..");
}

export function isSafeImageFileName(fileName: string): boolean {
  return /^[A-Za-z0-9-]{1,80}\.jpg$/.test(fileName);
}

export function isValidDayKey(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

export function isJpegBytes(bytes: Uint8Array): boolean {
  return bytes.byteLength >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

export function timingSafeEqualStrings(left: string, right: string): boolean {
  const a = textEncoder.encode(left);
  const b = textEncoder.encode(right);
  if (a.length === 0 || b.length === 0) {
    return false;
  }
  const maxLen = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let index = 0; index < maxLen; index += 1) {
    diff |= a[index % a.length] ^ b[index % b.length];
  }
  return diff === 0;
}

export function isAuthorized(request: Request, writeToken: string | undefined): boolean {
  if (typeof writeToken !== "string" || writeToken.length === 0) {
    return false;
  }
  const header = request.headers.get("authorization");
  if (!header) {
    return false;
  }
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  if (!match) {
    return false;
  }
  return timingSafeEqualStrings(match[1], writeToken);
}

export function parseRoute(method: string, pathname: string): RouteParseResult {
  const parts = pathname.split("/").filter(Boolean);
  if (parts.length < 3 || parts[0] !== "v1") {
    return { ok: false, status: 404, error: "not_found" };
  }

  let deviceKey: string;
  try {
    deviceKey = decodeURIComponent(parts[2]);
  } catch {
    return { ok: false, status: 400, error: "invalid_encoding" };
  }

  if (!isValidDeviceKey(deviceKey)) {
    return { ok: false, status: 400, error: "invalid_device_key" };
  }

  if (parts.length === 3 && parts[1] === "snapshot") {
    if (method === "GET") {
      return { ok: true, route: { action: "getSnapshot", deviceKey, requiresAuth: false } };
    }
    if (method === "PUT") {
      return { ok: true, route: { action: "putSnapshot", deviceKey, requiresAuth: true } };
    }
    return { ok: false, status: 405, error: "method_not_allowed" };
  }

  if (parts.length === 3 && parts[1] === "checkin") {
    if (method === "POST") {
      return { ok: true, route: { action: "checkIn", deviceKey, requiresAuth: true } };
    }
    return { ok: false, status: 405, error: "method_not_allowed" };
  }

  if (parts.length === 3 && parts[1] === "backup") {
    if (method === "GET") {
      return { ok: true, route: { action: "getBackup", deviceKey, requiresAuth: true } };
    }
    if (method === "PUT") {
      return { ok: true, route: { action: "putBackup", deviceKey, requiresAuth: true } };
    }
    return { ok: false, status: 405, error: "method_not_allowed" };
  }

  if (parts.length === 3 && parts[1] === "images") {
    if (method === "GET") {
      return { ok: true, route: { action: "getImages", deviceKey, requiresAuth: true } };
    }
    if (method === "PUT") {
      return { ok: true, route: { action: "putImages", deviceKey, requiresAuth: true } };
    }
    return { ok: false, status: 405, error: "method_not_allowed" };
  }

  if (parts.length === 4 && parts[1] === "image") {
    let imageFile: string;
    try {
      imageFile = decodeURIComponent(parts[3]);
    } catch {
      return { ok: false, status: 400, error: "invalid_encoding" };
    }
    if (!isSafeImageFileName(imageFile)) {
      return { ok: false, status: 400, error: "invalid_image_name" };
    }
    if (method === "PUT") {
      return { ok: true, route: { action: "putImage", deviceKey, imageFile, requiresAuth: true } };
    }
    if (method === "GET") {
      return { ok: true, route: { action: "getImage", deviceKey, imageFile, requiresAuth: false } };
    }
    return { ok: false, status: 405, error: "method_not_allowed" };
  }

  return { ok: false, status: 404, error: "not_found" };
}

export function buildForwardedRequest(request: Request, route: ParsedRoute): Request {
  const sanitizedHeaders = new Headers();
  for (const [key, value] of request.headers.entries()) {
    if (key.toLowerCase().startsWith("x-habitbloom-")) {
      continue;
    }
    sanitizedHeaders.set(key, value);
  }
  sanitizedHeaders.set(INTERNAL_ACTION_HEADER, route.action);
  sanitizedHeaders.set(INTERNAL_DEVICE_KEY_HEADER, route.deviceKey);
  if (route.imageFile) {
    sanitizedHeaders.set(INTERNAL_IMAGE_FILE_HEADER, route.imageFile);
  }

  const init: RequestInit = {
    method: request.method,
    headers: sanitizedHeaders
  };
  if (request.method !== "GET" && request.method !== "HEAD" && request.body !== null) {
    init.body = request.body;
    (init as RequestInit & { duplex?: "half" }).duplex = "half";
  }
  return new Request(request.url, init);
}

export async function handleWorkerRequest(
  request: Request,
  writeToken: string | undefined,
  dispatchToObject: (deviceKey: string, forwarded: Request) => Promise<Response>
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return empty(204);
  }

  const url = new URL(request.url);
  const parsed = parseRoute(request.method, url.pathname);
  if (!parsed.ok) {
    return json({ error: parsed.error }, parsed.status);
  }

  if (parsed.route.requiresAuth && !isAuthorized(request, writeToken)) {
    return json({ error: "unauthorized" }, 401);
  }

  const forwarded = buildForwardedRequest(request, parsed.route);
  return dispatchToObject(parsed.route.deviceKey, forwarded);
}

export class HabitSnapshotController {
  private readonly storage: StorageAdapter;
  private readonly nowProvider: () => Date;

  constructor(storage: StorageAdapter, nowProvider: () => Date = () => new Date()) {
    this.storage = storage;
    this.nowProvider = nowProvider;
  }

  async handle(request: Request): Promise<Response> {
    const action = request.headers.get(INTERNAL_ACTION_HEADER);
    const deviceKey = request.headers.get(INTERNAL_DEVICE_KEY_HEADER) ?? "";

    if (!isValidDeviceKey(deviceKey)) {
      return json({ error: "invalid_device_key" }, 400);
    }

    if (action === "getSnapshot") {
      const snapshot = await this.loadSnapshot(deviceKey);
      return json(snapshot);
    }

    if (action === "putSnapshot") {
      const parsed = await readJsonBody(request, MAX_JSON_BYTES);
      if (!parsed.ok) {
        return json({ error: parsed.error }, parsed.status);
      }
      const normalized = normalizeSnapshot(parsed.value, deviceKey, this.nowProvider());
      if (!normalized.ok) {
        return json({ error: normalized.error }, 400);
      }
      await this.storage.put(snapshotKey, normalized.value);
      return json(normalized.value);
    }

    if (action === "checkIn") {
      const parsed = await readJsonBody(request, MAX_JSON_BYTES);
      if (!parsed.ok) {
        return json({ error: parsed.error }, parsed.status);
      }
      const validated = validateCheckInRequest(parsed.value);
      if (!validated.ok) {
        return json({ error: validated.error }, 400);
      }
      const snapshot = await this.applyCheckIn(deviceKey, validated.value);
      return json(snapshot);
    }

    if (action === "getBackup") {
      const backup = await this.loadBackup(deviceKey);
      return json(backup);
    }

    if (action === "putBackup") {
      const parsed = await readJsonBody(request, MAX_JSON_BYTES);
      if (!parsed.ok) {
        return json({ error: parsed.error }, parsed.status);
      }
      const normalized = normalizeBackup(parsed.value, deviceKey, this.nowProvider());
      if (!normalized.ok) {
        return json({ error: normalized.error }, 400);
      }
      await this.storage.put(backupKey, normalized.value);
      return json(normalized.value);
    }

    if (action === "putImage") {
      const fileName = request.headers.get(INTERNAL_IMAGE_FILE_HEADER) ?? "";
      if (!isSafeImageFileName(fileName)) {
        return json({ error: "invalid_image_name" }, 400);
      }
      const contentType = request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() ?? "";
      if (contentType && contentType !== "image/jpeg" && contentType !== "application/octet-stream") {
        return json({ error: "unsupported_media_type" }, 415);
      }
      const bodyBytes = await readLimitedBytes(request, MAX_IMAGE_BYTES);
      if (!bodyBytes.ok) {
        return json({ error: bodyBytes.error }, bodyBytes.status);
      }
      if (bodyBytes.bytes.byteLength === 0) {
        return json({ error: "invalid_image_size" }, 400);
      }
      if (!isJpegBytes(bodyBytes.bytes)) {
        return json({ error: "unsupported_media_type" }, 415);
      }
      const storedBuffer = bodyBytes.bytes.slice().buffer;
      await this.storage.put(imagePrefix + fileName, storedBuffer);
      const manifest = await this.loadImageManifest();
      if (!manifest.files.includes(fileName)) {
        manifest.files = [...manifest.files, fileName].sort();
        await this.storage.put(imageManifestKey, manifest);
      }
      return json({ file: fileName, bytes: storedBuffer.byteLength });
    }

    if (action === "getImage") {
      const fileName = request.headers.get(INTERNAL_IMAGE_FILE_HEADER) ?? "";
      if (!isSafeImageFileName(fileName)) {
        return json({ error: "invalid_image_name" }, 400);
      }
      const raw = await this.storage.get<ArrayBuffer | Uint8Array>(imagePrefix + fileName);
      if (!raw) {
        return json({ error: "not_found" }, 404);
      }
      const payload = raw instanceof Uint8Array ? raw.slice().buffer : raw;
      return new Response(payload, {
        status: 200,
        headers: {
          "content-type": "image/jpeg",
          "cache-control": "private, max-age=86400",
          "x-content-type-options": "nosniff",
          ...corsHeaders()
        }
      });
    }

    if (action === "getImages") {
      return json(await this.loadImageManifest());
    }

    if (action === "putImages") {
      const parsed = await readJsonBody(request, MAX_JSON_BYTES);
      if (!parsed.ok) {
        return json({ error: parsed.error }, parsed.status);
      }
      const normalized = parseImageManifestInput(parsed.value);
      if (!normalized.ok) {
        return json({ error: normalized.error }, 400);
      }
      const manifest: ImageManifest = { files: normalized.files };
      await this.storage.put(imageManifestKey, manifest);
      const keepKeys = new Set(manifest.files.map((file) => imagePrefix + file));
      const storedImages = await this.storage.list({ prefix: imagePrefix });
      const staleKeys: string[] = [];
      for (const key of storedImages.keys()) {
        if (!keepKeys.has(key)) {
          staleKeys.push(key);
        }
      }
      if (staleKeys.length > 0) {
        await this.storage.delete(staleKeys);
      }
      return json({ files: manifest.files, deleted: staleKeys.length });
    }

    return json({ error: "not_found" }, 404);
  }

  private async loadImageManifest(): Promise<ImageManifest> {
    const existing = await this.storage.get<ImageManifest>(imageManifestKey);
    if (existing && Array.isArray(existing.files)) {
      const valid = existing.files.filter(
        (file): file is string => typeof file === "string" && isSafeImageFileName(file)
      );
      return { files: [...new Set(valid)].sort() };
    }
    return { files: [] };
  }

  private async loadSnapshot(deviceKey: string): Promise<WidgetSnapshot> {
    const existing = await this.storage.get<WidgetSnapshot>(snapshotKey);
    if (existing) {
      return existing;
    }
    const nowIso = this.nowProvider().toISOString();
    return {
      deviceKey,
      updatedAt: nowIso,
      dayKey: nowIso.slice(0, 10),
      selectedHabitID: null,
      habits: []
    };
  }

  private async applyCheckIn(deviceKey: string, body: CheckInRequest): Promise<WidgetSnapshot> {
    const now = this.nowProvider();
    const nowIso = now.toISOString();
    const targetDayKey = isValidDayKey(body.dayKey)
      ? body.dayKey
      : (body.snapshot && isValidDayKey(body.snapshot.dayKey) ? body.snapshot.dayKey : nowIso.slice(0, 10));

    const existing = await this.storage.get<WidgetSnapshot>(snapshotKey);
    const incomingSnapshot = body.snapshot ? normalizeSnapshot(body.snapshot, deviceKey, now) : null;
    const normalizedIncoming = incomingSnapshot && incomingSnapshot.ok ? incomingSnapshot.value : null;

    let base: WidgetSnapshot;
    if (existing && existing.habits.length > 0) {
      const existingDayKey = isValidDayKey(existing.dayKey)
        ? existing.dayKey
        : existing.updatedAt.slice(0, 10);
      const rolledHabits = existingDayKey === targetDayKey
        ? existing.habits.map((habit) => ({ ...habit }))
        : existing.habits.map((habit) => ({
            ...habit,
            isCompletedToday: false
          }));

      const existingById = new Map(rolledHabits.map((habit) => [habit.id, habit]));
      if (normalizedIncoming) {
        for (const incomingHabit of normalizedIncoming.habits) {
          if (!existingById.has(incomingHabit.id)) {
            rolledHabits.push({
              ...incomingHabit,
              isCompletedToday: existingDayKey === targetDayKey ? incomingHabit.isCompletedToday : false
            });
            existingById.set(incomingHabit.id, rolledHabits[rolledHabits.length - 1]);
          } else if (incomingHabit.id === body.habitID) {
            const current = existingById.get(incomingHabit.id)!;
            current.name = incomingHabit.name;
            current.icon = incomingHabit.icon;
            current.colorName = incomingHabit.colorName;
            current.cardStyle = incomingHabit.cardStyle;
            current.imageFileName = incomingHabit.imageFileName;
            current.completionRate = incomingHabit.completionRate;
          }
        }
      }

      base = {
        deviceKey,
        updatedAt: nowIso,
        dayKey: targetDayKey,
        selectedHabitID: body.habitID,
        habits: rolledHabits
      };
    } else if (normalizedIncoming) {
      const incomingDayKey = isValidDayKey(normalizedIncoming.dayKey)
        ? normalizedIncoming.dayKey
        : normalizedIncoming.updatedAt.slice(0, 10);
      base = {
        ...normalizedIncoming,
        deviceKey,
        updatedAt: nowIso,
        dayKey: targetDayKey,
        selectedHabitID: body.habitID,
        habits: incomingDayKey === targetDayKey
          ? normalizedIncoming.habits
          : normalizedIncoming.habits.map((habit) => ({ ...habit, isCompletedToday: false }))
      };
    } else {
      base = {
        deviceKey,
        updatedAt: nowIso,
        dayKey: targetDayKey,
        selectedHabitID: body.habitID,
        habits: []
      };
    }

    const incomingTarget = normalizedIncoming?.habits.find((habit) => habit.id === body.habitID);
    base.habits = base.habits.map((habit) => {
      if (habit.id !== body.habitID) {
        return habit;
      }
      const changed = habit.isCompletedToday !== body.isCompletedToday;
      let streakDays = habit.streakDays;
      let totalDays = habit.totalDays;
      if (incomingTarget && incomingTarget.isCompletedToday === body.isCompletedToday && existing === undefined) {
        streakDays = incomingTarget.streakDays;
        totalDays = incomingTarget.totalDays;
      } else if (changed) {
        if (body.isCompletedToday) {
          streakDays = Math.max(1, habit.streakDays + 1);
          totalDays = Math.max(1, habit.totalDays + 1);
        } else {
          streakDays = Math.max(0, habit.streakDays - 1);
          totalDays = Math.max(0, habit.totalDays - 1);
        }
      }
      return {
        ...habit,
        isCompletedToday: body.isCompletedToday,
        streakDays,
        totalDays,
        updatedAt: nowIso
      };
    });

    await this.storage.put(snapshotKey, base);
    return base;
  }

  private async loadBackup(deviceKey: string): Promise<BackupArchive> {
    const existing = await this.storage.get<BackupArchive>(backupKey);
    if (existing) {
      return existing;
    }
    return {
      version: 1,
      deviceKey,
      exportedAt: this.nowProvider().toISOString(),
      habits: []
    };
  }
}

async function readLimitedBytes(
  request: Request,
  maxBytes: number
): Promise<{ ok: true; bytes: Uint8Array } | { ok: false; status: number; error: string }> {
  const contentLengthHeader = request.headers.get("content-length");
  if (contentLengthHeader !== null) {
    const parsedLength = Number(contentLengthHeader);
    if (Number.isFinite(parsedLength) && parsedLength > maxBytes) {
      return { ok: false, status: 413, error: "payload_too_large" };
    }
  }

  if (!request.body) {
    return { ok: true, bytes: new Uint8Array(0) };
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      if (value) {
        total += value.byteLength;
        if (total > maxBytes) {
          await reader.cancel().catch(() => {});
          return { ok: false, status: 413, error: "payload_too_large" };
        }
        chunks.push(value);
      }
    }
  } finally {
    reader.releaseLock();
  }

  const combined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    combined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { ok: true, bytes: combined };
}

async function readJsonBody(
  request: Request,
  maxBytes: number
): Promise<{ ok: true; value: unknown } | { ok: false; status: number; error: string }> {
  const body = await readLimitedBytes(request, maxBytes);
  if (!body.ok) {
    return body;
  }
  if (body.bytes.byteLength === 0) {
    return { ok: false, status: 400, error: "invalid_json" };
  }
  try {
    const text = textDecoder.decode(body.bytes);
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, status: 400, error: "invalid_json" };
  }
}

function parseImageManifestInput(
  value: unknown
): { ok: true; files: string[] } | { ok: false; error: string } {
  let rawFiles: unknown[] | null = null;
  if (Array.isArray(value)) {
    rawFiles = value;
  } else if (isRecord(value) && Array.isArray(value.files)) {
    rawFiles = value.files;
  }
  if (!rawFiles) {
    return { ok: false, error: "invalid_image_manifest" };
  }
  const files = rawFiles
    .filter((entry): entry is string => typeof entry === "string" && isSafeImageFileName(entry));
  return { ok: true, files: [...new Set(files)].sort() };
}

function validateCheckInRequest(
  value: unknown
): { ok: true; value: CheckInRequest } | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "invalid_checkin" };
  }
  if (typeof value.habitID !== "string" || value.habitID.trim().length === 0 || value.habitID.length > 64) {
    return { ok: false, error: "invalid_habit_id" };
  }
  if (typeof value.isCompletedToday !== "boolean") {
    return { ok: false, error: "invalid_completion_flag" };
  }
  return {
    ok: true,
    value: {
      habitID: value.habitID.trim(),
      isCompletedToday: value.isCompletedToday,
      dayKey: isValidDayKey(value.dayKey) ? value.dayKey : null,
      snapshot: isRecord(value.snapshot) ? (value.snapshot as WidgetSnapshot) : null
    }
  };
}

function normalizeSnapshot(
  value: unknown,
  deviceKey: string,
  now: Date
): { ok: true; value: WidgetSnapshot } | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "invalid_snapshot" };
  }
  if (value.habits !== undefined && !Array.isArray(value.habits)) {
    return { ok: false, error: "invalid_snapshot_habits" };
  }

  const nowIso = now.toISOString();
  const habitsValue = Array.isArray(value.habits) ? value.habits.slice(0, MAX_HABITS) : [];
  const dayKey = isValidDayKey(value.dayKey) ? value.dayKey : nowIso.slice(0, 10);

  return {
    ok: true,
    value: {
      deviceKey,
      updatedAt: nowIso,
      dayKey,
      selectedHabitID: typeof value.selectedHabitID === "string" ? value.selectedHabitID.slice(0, 64) : null,
      habits: habitsValue
        .map((entry) => normalizeHabit(entry, nowIso))
        .filter((habit): habit is HabitSnapshot => habit !== null)
    }
  };
}

function normalizeHabit(value: unknown, fallbackIso: string): HabitSnapshot | null {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.name !== "string") {
    return null;
  }
  const safeImageFileName =
    typeof value.imageFileName === "string" && isSafeImageFileName(value.imageFileName)
      ? value.imageFileName
      : null;
  const safeImageData =
    typeof value.imageData === "string" && value.imageData.length <= MAX_EMBEDDED_IMAGE_BASE64_LENGTH
      ? value.imageData
      : null;

  return {
    id: value.id.slice(0, 64),
    name: value.name.slice(0, 120),
    icon: typeof value.icon === "string" ? value.icon.slice(0, 64) : "checkmark.circle.fill",
    colorName: typeof value.colorName === "string" ? value.colorName.slice(0, 32) : "mint",
    cardStyle: typeof value.cardStyle === "string" ? value.cardStyle.slice(0, 32) : "soft",
    streakDays: Math.max(0, Math.floor(toNumber(value.streakDays))),
    totalDays: Math.max(0, Math.floor(toNumber(value.totalDays))),
    completionRate: Math.min(1, Math.max(0, toNumber(value.completionRate))),
    isCompletedToday: value.isCompletedToday === true,
    imageFileName: safeImageFileName,
    imageData: safeImageData,
    updatedAt: toISODateString(value.updatedAt, fallbackIso)
  };
}

function normalizeBackup(
  value: unknown,
  deviceKey: string,
  now: Date
): { ok: true; value: BackupArchive } | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "invalid_backup" };
  }
  if (value.habits !== undefined && !Array.isArray(value.habits)) {
    return { ok: false, error: "invalid_backup_habits" };
  }

  const nowIso = now.toISOString();
  const habitsValue = Array.isArray(value.habits) ? value.habits.slice(0, MAX_HABITS) : [];
  return {
    ok: true,
    value: {
      version: 1,
      deviceKey,
      exportedAt: nowIso,
      habits: habitsValue
        .map((entry) => normalizeBackupHabit(entry, nowIso))
        .filter((habit): habit is BackupHabit => habit !== null)
    }
  };
}

function normalizeBackupHabit(value: unknown, fallbackIso: string): BackupHabit | null {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.name !== "string") {
    return null;
  }

  const checkInsValue = Array.isArray(value.checkIns) ? value.checkIns.slice(0, MAX_CHECKINS_PER_HABIT) : [];
  return {
    id: value.id.slice(0, 64),
    name: value.name.slice(0, 120),
    icon: typeof value.icon === "string" ? value.icon.slice(0, 64) : "checkmark.circle.fill",
    colorName: typeof value.colorName === "string" ? value.colorName.slice(0, 32) : undefined,
    cardStyle: typeof value.cardStyle === "string" ? value.cardStyle.slice(0, 32) : undefined,
    targetWeekdayMask: clampInteger(value.targetWeekdayMask, 1, 127, 127),
    reminderEnabled: value.reminderEnabled === true,
    reminderHour: clampInteger(value.reminderHour, 0, 23, 20),
    reminderMinute: clampInteger(value.reminderMinute, 0, 59, 0),
    reminderWeekdayMask: clampInteger(value.reminderWeekdayMask, 1, 127, 127),
    sortOrder: clampInteger(value.sortOrder, 0, 100_000, 0),
    createdAt: toISODateString(value.createdAt, fallbackIso),
    checkIns: checkInsValue
      .map((entry) => normalizeBackupCheckIn(entry, fallbackIso))
      .filter((checkIn): checkIn is BackupCheckIn => checkIn !== null)
  };
}

function normalizeBackupCheckIn(value: unknown, fallbackIso: string): BackupCheckIn | null {
  if (!isRecord(value) || typeof value.id !== "string") {
    return null;
  }

  return {
    id: value.id.slice(0, 64),
    day: toISODateString(value.day, fallbackIso),
    isCompleted: value.isCompleted === true,
    note: typeof value.note === "string" ? value.note.slice(0, 4_000) : "",
    createdAt: toISODateString(value.createdAt, fallbackIso)
  };
}

function toNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function toInteger(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isInteger(value) ? value : fallback;
}

function clampInteger(value: unknown, minimum: number, maximum: number, fallback: number): number {
  const integer = toInteger(value, fallback);
  return Math.min(maximum, Math.max(minimum, integer));
}

function toISODateString(value: unknown, fallbackIso: string): string {
  if (typeof value === "string" && !Number.isNaN(Date.parse(value))) {
    return new Date(value).toISOString();
  }
  return fallbackIso;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...corsHeaders()
    }
  });
}

export function empty(status: number): Response {
  return new Response(null, {
    status,
    headers: {
      "x-content-type-options": "nosniff",
      ...corsHeaders()
    }
  });
}

function corsHeaders(): HeadersInit {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, PUT, POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type, cache-control"
  };
}
