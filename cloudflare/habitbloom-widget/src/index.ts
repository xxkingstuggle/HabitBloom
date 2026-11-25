import { DurableObject } from "cloudflare:workers";
import {
  HabitSnapshotController,
  handleWorkerRequest,
  type StorageAdapter
} from "./core";

export interface Env {
  HABIT_SNAPSHOT: DurableObjectNamespace<HabitSnapshotObject>;
  WRITE_TOKEN?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handleWorkerRequest(request, env.WRITE_TOKEN, async (deviceKey, forwarded) => {
      const objectID = env.HABIT_SNAPSHOT.idFromName(deviceKey);
      const object = env.HABIT_SNAPSHOT.get(objectID);
      return object.fetch(forwarded);
    });
  }
};

export class HabitSnapshotObject extends DurableObject {
  private readonly controller: HabitSnapshotController;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.controller = new HabitSnapshotController(ctx.storage as unknown as StorageAdapter);
  }

  async fetch(request: Request): Promise<Response> {
    return this.controller.handle(request);
  }
}
