import assert from "node:assert/strict";
import test from "node:test";
import {
  HabitSnapshotController,
  MAX_IMAGE_BYTES,
  MAX_JSON_BYTES,
  handleWorkerRequest,
  isAuthorized,
  isJpegBytes,
  isValidDeviceKey,
  parseRoute,
  timingSafeEqualStrings
} from "../src/core.ts";

class MemoryStorage {
  constructor() {
    this.map = new Map();
  }

  async get(key) {
    return this.map.get(key);
  }

  async put(key, value) {
    this.map.set(key, value);
  }

  async delete(keys) {
    if (Array.isArray(keys)) {
      let count = 0;
      for (const key of keys) {
        if (this.map.delete(key)) {
          count += 1;
        }
      }
      return count;
    }
    return this.map.delete(keys);
  }

  async list(options) {
    const prefix = options?.prefix ?? "";
    const result = new Map();
    for (const [key, value] of this.map.entries()) {
      if (key.startsWith(prefix)) {
        result.set(key, value);
      }
    }
    return result;
  }
}

function createHarness(initialNow = "2026-11-25T10:00:00.123Z", token = "super-secret-write-token-123456") {
  let currentNow = new Date(initialNow);
  const objects = new Map();

  const getObject = (deviceKey) => {
    if (!objects.has(deviceKey)) {
      const storage = new MemoryStorage();
      objects.set(deviceKey, {
        storage,
        controller: new HabitSnapshotController(storage, () => new Date(currentNow.getTime()))
      });
    }
    return objects.get(deviceKey);
  };

  const fetch = (path, init = {}) => {
    const request = new Request(`https://habitbloom.example${path}`, init);
    return handleWorkerRequest(request, token, (deviceKey, forwarded) =>
      getObject(deviceKey).controller.handle(forwarded)
    );
  };

  return {
    fetch,
    getObject,
    setNow(iso) {
      currentNow = new Date(iso);
    },
    authHeaders(extra = {}) {
      return { authorization: `Bearer ${token}`, ...extra };
    }
  };
}

function makeFakeJpeg(size = 64) {
  const bytes = new Uint8Array(size);
  bytes[0] = 0xff;
  bytes[1] = 0xd8;
  bytes[2] = 0xff;
  bytes[3] = 0xe0;
  bytes[size - 2] = 0xff;
  bytes[size - 1] = 0xd9;
  return bytes;
}

test("auth requires non-empty WRITE_TOKEN and strict Bearer prefix", () => {
  assert.equal(timingSafeEqualStrings("abc", "abc"), true);
  assert.equal(timingSafeEqualStrings("abc", "abd"), false);
  assert.equal(timingSafeEqualStrings("abc", "abcd"), false);
  assert.equal(timingSafeEqualStrings("", ""), false);

  const withBearer = new Request("https://habitbloom.example/v1/snapshot/device-1234", {
    headers: { authorization: "Bearer secret-token" }
  });
  const rawToken = new Request("https://habitbloom.example/v1/snapshot/device-1234", {
    headers: { authorization: "secret-token" }
  });

  assert.equal(isAuthorized(withBearer, "secret-token"), true);
  assert.equal(isAuthorized(withBearer, undefined), false);
  assert.equal(isAuthorized(withBearer, ""), false);
  assert.equal(isAuthorized(rawToken, "secret-token"), false);
});

test("route validation blocks malformed URI encoding, bad deviceKey, traversal, and spoofed internal headers", async () => {
  assert.equal(isValidDeviceKey("device_1234-ok.key"), true);
  assert.equal(isValidDeviceKey("../etc"), false);
  assert.equal(isValidDeviceKey("a..b-1234"), false);
  assert.equal(isValidDeviceKey("abc"), false);

  assert.deepEqual(parseRoute("GET", "/v1/snapshot/%E0%A4%A"), {
    ok: false,
    status: 400,
    error: "invalid_encoding"
  });

  const harness = createHarness();
  const badEncoding = await harness.fetch("/v1/snapshot/%E0%A4%A");
  assert.equal(badEncoding.status, 400);

  const badDeviceKey = await harness.fetch("/v1/snapshot/bad%2Fkey");
  assert.equal(badDeviceKey.status, 400);

  const spoofed = await harness.fetch("/v1/snapshot/device-alpha-1234", {
    headers: {
      "x-habitbloom-action": "putSnapshot",
      "x-habitbloom-device-key": "victim-device-9999"
    }
  });
  assert.equal(spoofed.status, 200);
  const body = await spoofed.json();
  assert.equal(body.deviceKey, "device-alpha-1234");
  assert.deepEqual(body.habits, []);
});

test("JSON endpoints reject malformed JSON and oversized payloads cleanly", async () => {
  const harness = createHarness();

  const malformed = await harness.fetch("/v1/snapshot/device-alpha-1234", {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "application/json" }),
    body: "{not-json"
  });
  assert.equal(malformed.status, 400);

  const tooLarge = await harness.fetch("/v1/snapshot/device-alpha-1234", {
    method: "PUT",
    headers: harness.authHeaders({
      "content-type": "application/json",
      "content-length": String(MAX_JSON_BYTES + 1)
    }),
    body: JSON.stringify({ habits: [] })
  });
  assert.equal(tooLarge.status, 413);
});

test("image upload validates JPEG magic bytes, headers, manifest object/array compatibility, and orphan cleanup", async () => {
  assert.equal(isJpegBytes(makeFakeJpeg()), true);
  assert.equal(isJpegBytes(new Uint8Array([0x3c, 0x73, 0x76, 0x67])), false);

  const harness = createHarness();
  const deviceKey = "device-images-1234";

  const badFormat = await harness.fetch(`/v1/image/${deviceKey}/habit-1-abcd.jpg`, {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "image/jpeg" }),
    body: new Uint8Array([0x89, 0x50, 0x4e, 0x47])
  });
  assert.equal(badFormat.status, 400);

  const badMime = await harness.fetch(`/v1/image/${deviceKey}/habit-1-abcd.jpg`, {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "image/svg+xml" }),
    body: makeFakeJpeg()
  });
  assert.equal(badMime.status, 415);

  const oversizeImage = await harness.fetch(`/v1/image/${deviceKey}/habit-1-abcd.jpg`, {
    method: "PUT",
    headers: harness.authHeaders({
      "content-type": "image/jpeg",
      "content-length": String(MAX_IMAGE_BYTES + 1)
    }),
    body: makeFakeJpeg()
  });
  assert.equal(oversizeImage.status, 413);

  const uploadA = await harness.fetch(`/v1/image/${deviceKey}/habit-a-1111.jpg`, {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "image/jpeg" }),
    body: makeFakeJpeg(48)
  });
  assert.equal(uploadA.status, 200);

  const uploadB = await harness.fetch(`/v1/image/${deviceKey}/habit-b-2222.jpg`, {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "image/jpeg" }),
    body: makeFakeJpeg(56)
  });
  assert.equal(uploadB.status, 200);

  const fetchedA = await harness.fetch(`/v1/image/${deviceKey}/habit-a-1111.jpg`);
  assert.equal(fetchedA.status, 200);
  assert.equal(fetchedA.headers.get("cache-control"), "private, max-age=86400");
  assert.equal(fetchedA.headers.get("x-content-type-options"), "nosniff");

  const updateManifestObj = await harness.fetch(`/v1/images/${deviceKey}`, {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({ files: ["habit-b-2222.jpg"] })
  });
  assert.equal(updateManifestObj.status, 200);
  const manifestPayload = await updateManifestObj.json();
  assert.deepEqual(manifestPayload.files, ["habit-b-2222.jpg"]);
  assert.equal(manifestPayload.deleted, 1);

  const deletedA = await harness.fetch(`/v1/image/${deviceKey}/habit-a-1111.jpg`);
  assert.equal(deletedA.status, 404);

  const updateManifestArr = await harness.fetch(`/v1/images/${deviceKey}`, {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "application/json" }),
    body: JSON.stringify(["habit-b-2222.jpg"])
  });
  assert.equal(updateManifestArr.status, 200);
  assert.deepEqual((await updateManifestArr.json()).files, ["habit-b-2222.jpg"]);
});

test("checkIn merges incrementally without stale snapshot clobbering and rolls over across midnight", async () => {
  const harness = createHarness("2026-11-25T10:00:00.000Z");
  const deviceKey = "device-sync-1234";

  const initialSnapshot = {
    deviceKey,
    dayKey: "2026-11-25",
    habits: [
      { id: "h1", name: "阅读", icon: "book.closed.fill", colorName: "mint", streakDays: 2, totalDays: 5, isCompletedToday: false },
      { id: "h2", name: "跑步", icon: "figure.run", colorName: "coral", streakDays: 4, totalDays: 10, isCompletedToday: false }
    ]
  };

  const putResp = await harness.fetch(`/v1/snapshot/${deviceKey}`, {
    method: "PUT",
    headers: harness.authHeaders({ "content-type": "application/json" }),
    body: JSON.stringify(initialSnapshot)
  });
  assert.equal(putResp.status, 200);

  const checkIn1 = await harness.fetch(`/v1/checkin/${deviceKey}`, {
    method: "POST",
    headers: harness.authHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({ habitID: "h1", isCompletedToday: true, dayKey: "2026-11-25" })
  });
  assert.equal(checkIn1.status, 200);
  const after1 = await checkIn1.json();
  assert.equal(after1.habits.find((h) => h.id === "h1").isCompletedToday, true);
  assert.equal(after1.habits.find((h) => h.id === "h1").streakDays, 3);

  const checkIn2 = await harness.fetch(`/v1/checkin/${deviceKey}`, {
    method: "POST",
    headers: harness.authHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({
      habitID: "h2",
      isCompletedToday: true,
      dayKey: "2026-11-25",
      snapshot: initialSnapshot
    })
  });
  assert.equal(checkIn2.status, 200);
  const after2 = await checkIn2.json();
  assert.equal(after2.habits.find((h) => h.id === "h1").isCompletedToday, true, "h1 completion must survive concurrent h2 check-in");
  assert.equal(after2.habits.find((h) => h.id === "h2").isCompletedToday, true);

  harness.setNow("2026-11-26T08:30:00.000Z");
  const nextDayCheckIn = await harness.fetch(`/v1/checkin/${deviceKey}`, {
    method: "POST",
    headers: harness.authHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({ habitID: "h2", isCompletedToday: true, dayKey: "2026-11-26" })
  });
  assert.equal(nextDayCheckIn.status, 200);
  const afterRollover = await nextDayCheckIn.json();
  assert.equal(afterRollover.dayKey, "2026-11-26");
  assert.equal(afterRollover.habits.find((h) => h.id === "h1").isCompletedToday, false, "yesterday completion must roll over to false");
  assert.equal(afterRollover.habits.find((h) => h.id === "h2").isCompletedToday, true);
});
