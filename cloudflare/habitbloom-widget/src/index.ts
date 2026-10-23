import { DurableObject } from "cloudflare:workers";

export interface Env {
  HABIT_SNAPSHOT: DurableObjectNamespace<HabitSnapshotObject>;
  WRITE_TOKEN: string;
}

type HabitSnapshot = {
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

type WidgetSnapshot = {
  deviceKey: string;
  updatedAt: string;
  selectedHabitID?: string | null;
  habits: HabitSnapshot[];
};

type CheckInRequest = {
  habitID: string;
  isCompletedToday: boolean;
  snapshot?: WidgetSnapshot | null;
};

type ImageManifest = {
  files: string[];
};

type BackupCheckIn = {
  id: string;
  day: string;
  isCompleted: boolean;
  note?: string;
  createdAt: string;
};

type BackupHabit = {
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

type BackupArchive = {
  version: number;
  deviceKey: string;
  exportedAt: string;
  habits: BackupHabit[];
};

const snapshotKey = "snapshot";
const backupKey = "backup";
const imageManifestKey = "image-manifest";
const imagePrefix = "image/";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const route = parseRoute(request.method, url.pathname);

    if (request.method === "OPTIONS") {
      return empty(204);
    }

    if (!route) {
      return json({ error: "not_found" }, 404);
    }

    if (route.requiresAuth && !isAuthorized(request, env)) {
      return json({ error: "unauthorized" }, 401);
    }

    const objectID = env.HABIT_SNAPSHOT.idFromName(route.deviceKey);
    const object = env.HABIT_SNAPSHOT.get(objectID);
    const forwarded = new Request(request);
    forwarded.headers.set("x-habitbloom-action", route.action);
    forwarded.headers.set("x-habitbloom-device-key", route.deviceKey);
    if (route.imageFile) {
      forwarded.headers.set("x-habitbloom-image-file", route.imageFile);
    }
    return object.fetch(forwarded);
  }
};

export class HabitSnapshotObject extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    const action = request.headers.get("x-habitbloom-action");
    const deviceKey = request.headers.get("x-habitbloom-device-key") ?? "";

    if (action === "getSnapshot") {
      const snapshot = await this.loadSnapshot(deviceKey);
      return json(snapshot);
    }

    if (action === "putSnapshot") {
      const snapshot = normalizeSnapshot(await request.json(), deviceKey);
      await this.ctx.storage.put(snapshotKey, snapshot);
      return json(snapshot);
    }

    if (action === "checkIn") {
      const body = await request.json() as CheckInRequest;
      const snapshot = await this.applyCheckIn(deviceKey, body);
      return json(snapshot);
    }

    if (action === "getBackup") {
      const backup = await this.loadBackup(deviceKey);
      return json(backup);
    }

    if (action === "putBackup") {
      const backup = normalizeBackup(await request.json(), deviceKey);
      await this.ctx.storage.put(backupKey, backup);
      return json(backup);
    }

    if (action === "putImage") {
      const fileName = request.headers.get("x-habitbloom-image-file") ?? "";
      if (!isSafeImageFileName(fileName)) {
        return json({ error: "invalid_image_name" }, 400);
      }
      const bytes = await request.arrayBuffer();
      if (bytes.byteLength === 0 || bytes.byteLength > 2_000_000) {
        return json({ error: "invalid_image_size" }, 400);
      }
      await this.ctx.storage.put(imagePrefix + fileName, bytes);
      const manifest = await this.loadImageManifest();
      if (!manifest.files.includes(fileName)) {
        manifest.files.push(fileName);
        await this.ctx.storage.put(imageManifestKey, manifest);
      }
      return json({ file: fileName, bytes: bytes.byteLength });
    }

    if (action === "getImage") {
      const fileName = request.headers.get("x-habitbloom-image-file") ?? "";
      if (!isSafeImageFileName(fileName)) {
        return json({ error: "invalid_image_name" }, 400);
      }
      const bytes = await this.ctx.storage.get<ArrayBuffer>(imagePrefix + fileName);
      if (!bytes) {
        return json({ error: "not_found" }, 404);
      }
      return new Response(bytes, {
        status: 200,
        headers: {
          "content-type": "image/jpeg",
          "cache-control": "public, max-age=31536000, immutable",
          ...corsHeaders()
        }
      });
    }

    if (action === "getImages") {
      return json(await this.loadImageManifest());
    }

    if (action === "putImages") {
      const value = await request.json();
      const files = Array.isArray(value)
        ? value.filter((entry): entry is string => typeof entry === "string" && isSafeImageFileName(entry))
        : [];
      const manifest: ImageManifest = { files: [...new Set(files)].sort() };
      await this.ctx.storage.put(imageManifestKey, manifest);
      return json(manifest);
    }

    return json({ error: "not_found" }, 404);
  }

  private async loadImageManifest(): Promise<ImageManifest> {
    const existing = await this.ctx.storage.get<ImageManifest>(imageManifestKey);
    if (existing && Array.isArray(existing.files)) {
      return { files: existing.files.filter((file) => typeof file === "string") };
    }
    return { files: [] };
  }

  private async loadSnapshot(deviceKey: string): Promise<WidgetSnapshot> {
    const existing = await this.ctx.storage.get<WidgetSnapshot>(snapshotKey);
    if (existing) {
      return existing;
    }
    return {
      deviceKey,
      updatedAt: new Date().toISOString(),
      selectedHabitID: null,
      habits: []
    };
  }

  private async applyCheckIn(deviceKey: string, body: CheckInRequest): Promise<WidgetSnapshot> {
    const now = new Date().toISOString();
    if (body.snapshot) {
      const snapshot = normalizeSnapshot(body.snapshot, deviceKey);
      snapshot.selectedHabitID = body.habitID;
      snapshot.updatedAt = now;
      snapshot.habits = snapshot.habits.map((habit) =>
        habit.id === body.habitID
          ? { ...habit, isCompletedToday: body.isCompletedToday, updatedAt: now }
          : habit
      );
      await this.ctx.storage.put(snapshotKey, snapshot);
      return snapshot;
    }

    const snapshot = await this.loadSnapshot(deviceKey);
    snapshot.selectedHabitID = body.habitID;
    snapshot.updatedAt = now;
    snapshot.habits = snapshot.habits.map((habit) =>
      habit.id === body.habitID
        ? { ...habit, isCompletedToday: body.isCompletedToday, updatedAt: now }
        : habit
    );
    await this.ctx.storage.put(snapshotKey, snapshot);
    return snapshot;
  }

  private async loadBackup(deviceKey: string): Promise<BackupArchive> {
    const existing = await this.ctx.storage.get<BackupArchive>(backupKey);
    if (existing) {
      return existing;
    }
    return {
      version: 1,
      deviceKey,
      exportedAt: new Date().toISOString(),
      habits: []
    };
  }
}

function parseRoute(method: string, pathname: string):
  | {
      action: "getSnapshot" | "putSnapshot" | "checkIn" | "getBackup" | "putBackup" | "putImage" | "getImage" | "getImages" | "putImages";
      deviceKey: string;
      imageFile?: string;
      requiresAuth: boolean;
    }
  | null {
  const parts = pathname.split("/").filter(Boolean);
  if (parts.length < 3 || parts[0] !== "v1") {
    return null;
  }

  const deviceKey = decodeURIComponent(parts[2]);
  if (!deviceKey) {
    return null;
  }

  if (parts.length === 3 && parts[1] === "snapshot") {
    if (method === "GET") {
      return { action: "getSnapshot", deviceKey, requiresAuth: false };
    }
    if (method === "PUT") {
      return { action: "putSnapshot", deviceKey, requiresAuth: true };
    }
    return null;
  }

  if (parts.length === 3 && parts[1] === "checkin" && method === "POST") {
    return { action: "checkIn", deviceKey, requiresAuth: true };
  }

  if (parts.length === 3 && parts[1] === "backup") {
    if (method === "GET") {
      return { action: "getBackup", deviceKey, requiresAuth: true };
    }
    if (method === "PUT") {
      return { action: "putBackup", deviceKey, requiresAuth: true };
    }
    return null;
  }

  if (parts.length === 3 && parts[1] === "images") {
    if (method === "GET") {
      return { action: "getImages", deviceKey, requiresAuth: true };
    }
    if (method === "PUT") {
      return { action: "putImages", deviceKey, requiresAuth: true };
    }
    return null;
  }

  if (parts.length === 4 && parts[1] === "image") {
    const imageFile = decodeURIComponent(parts[3]);
    if (!imageFile) {
      return null;
    }
    if (method === "PUT") {
      return { action: "putImage", deviceKey, imageFile, requiresAuth: true };
    }
    if (method === "GET") {
      return { action: "getImage", deviceKey, imageFile, requiresAuth: false };
    }
    return null;
  }

  return null;
}

function isSafeImageFileName(fileName: string): boolean {
  return /^[A-Za-z0-9-]{1,80}\.jpg$/.test(fileName);
}

function isAuthorized(request: Request, env: Env): boolean {
  const header = request.headers.get("authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  return env.WRITE_TOKEN.length > 0 && token === env.WRITE_TOKEN;
}

function normalizeSnapshot(value: unknown, deviceKey: string): WidgetSnapshot {
  if (!isRecord(value)) {
    throw new Error("Invalid snapshot");
  }

  const habitsValue = Array.isArray(value.habits) ? value.habits : [];
  return {
    deviceKey,
    updatedAt: new Date().toISOString(),
    selectedHabitID: typeof value.selectedHabitID === "string" ? value.selectedHabitID : null,
    habits: habitsValue.map(normalizeHabit).filter((habit): habit is HabitSnapshot => habit !== null)
  };
}

function normalizeHabit(value: unknown): HabitSnapshot | null {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.name !== "string") {
    return null;
  }

  return {
    id: value.id,
    name: value.name,
    icon: typeof value.icon === "string" ? value.icon : "checkmark.circle.fill",
    colorName: typeof value.colorName === "string" ? value.colorName : "mint",
    cardStyle: typeof value.cardStyle === "string" ? value.cardStyle : "soft",
    streakDays: toNumber(value.streakDays),
    totalDays: toNumber(value.totalDays),
    completionRate: toNumber(value.completionRate),
    isCompletedToday: value.isCompletedToday === true,
    imageFileName: typeof value.imageFileName === "string" ? value.imageFileName : null,
    imageData: typeof value.imageData === "string" ? value.imageData : null,
    updatedAt: typeof value.updatedAt === "string" ? value.updatedAt : new Date().toISOString()
  };
}

function normalizeBackup(value: unknown, deviceKey: string): BackupArchive {
  if (!isRecord(value)) {
    throw new Error("Invalid backup");
  }

  const habitsValue = Array.isArray(value.habits) ? value.habits : [];
  return {
    version: 1,
    deviceKey,
    exportedAt: new Date().toISOString(),
    habits: habitsValue.map(normalizeBackupHabit).filter((habit): habit is BackupHabit => habit !== null)
  };
}

function normalizeBackupHabit(value: unknown): BackupHabit | null {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.name !== "string") {
    return null;
  }

  const checkInsValue = Array.isArray(value.checkIns) ? value.checkIns : [];
  return {
    id: value.id,
    name: value.name,
    icon: typeof value.icon === "string" ? value.icon : "checkmark.circle.fill",
    colorName: typeof value.colorName === "string" ? value.colorName : undefined,
    cardStyle: typeof value.cardStyle === "string" ? value.cardStyle : undefined,
    targetWeekdayMask: toInteger(value.targetWeekdayMask, 127),
    reminderEnabled: value.reminderEnabled === true,
    reminderHour: clampInteger(value.reminderHour, 0, 23, 20),
    reminderMinute: clampInteger(value.reminderMinute, 0, 59, 0),
    reminderWeekdayMask: toInteger(value.reminderWeekdayMask, 127),
    sortOrder: toInteger(value.sortOrder, 0),
    createdAt: toISODateString(value.createdAt),
    checkIns: checkInsValue.map(normalizeBackupCheckIn).filter((checkIn): checkIn is BackupCheckIn => checkIn !== null)
  };
}

function normalizeBackupCheckIn(value: unknown): BackupCheckIn | null {
  if (!isRecord(value) || typeof value.id !== "string") {
    return null;
  }

  return {
    id: value.id,
    day: toISODateString(value.day),
    isCompleted: value.isCompleted === true,
    note: typeof value.note === "string" ? value.note : "",
    createdAt: toISODateString(value.createdAt)
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

function toISODateString(value: unknown): string {
  if (typeof value === "string" && !Number.isNaN(Date.parse(value))) {
    return new Date(value).toISOString();
  }
  return new Date().toISOString();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...corsHeaders()
    }
  });
}

function empty(status: number): Response {
  return new Response(null, {
    status,
    headers: corsHeaders()
  });
}

function corsHeaders(): HeadersInit {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, PUT, POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type, cache-control"
  };
}
