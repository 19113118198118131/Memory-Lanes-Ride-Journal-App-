type OutboxItem = {
  id: string;
  recipient_id: string;
  group_ride_id: string | null;
  kind: string;
  title: string;
  body: string;
  deep_link: string | null;
  attempts: number;
};

type PushDevice = {
  id: string;
  token: string;
  environment: "development" | "production";
};

type Preferences = {
  quiet_hours: boolean;
  timezone: string;
};

const required = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const base64URL = (input: Uint8Array | string): string => {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

const importAPNsKey = async (pem: string): Promise<CryptoKey> => {
  const encoded = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const raw = Uint8Array.from(atob(encoded), character => character.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    raw,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
};

const makeAPNsJWT = async (): Promise<string> => {
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: required("APNS_KEY_ID") }));
  const claims = base64URL(JSON.stringify({
    iss: required("APNS_TEAM_ID"),
    iat: Math.floor(Date.now() / 1_000),
  }));
  const unsigned = `${header}.${claims}`;
  const key = await importAPNsKey(required("APNS_PRIVATE_KEY"));
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  ));
  return `${unsigned}.${base64URL(signature)}`;
};

const rest = async (path: string, init: RequestInit = {}): Promise<Response> => {
  const secret = required("SUPABASE_SERVICE_ROLE_KEY");
  const headers = new Headers(init.headers);
  headers.set("apikey", secret);
  headers.set("Authorization", `Bearer ${secret}`);
  headers.set("Content-Type", "application/json");
  return fetch(`${required("SUPABASE_URL")}/rest/v1/${path}`, { ...init, headers });
};

const patchOutbox = async (id: string, values: Record<string, unknown>) => {
  await rest(`notification_outbox?id=eq.${id}`, {
    method: "PATCH",
    body: JSON.stringify(values),
  });
};

const isQuietTime = (timezone: string): boolean => {
  try {
    const hour = Number(new Intl.DateTimeFormat("en-NZ", {
      hour: "2-digit",
      hourCycle: "h23",
      timeZone: timezone,
    }).format(new Date()));
    return hour >= 22 || hour < 7;
  } catch {
    return false;
  }
};

const sendToDevice = async (
  item: OutboxItem,
  device: PushDevice,
  jwt: string,
): Promise<Response> => {
  const host = device.environment === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";
  const shareToken = item.deep_link?.split("/").at(-1);
  return fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": required("APNS_TOPIC"),
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": `${item.kind}-${item.group_ride_id ?? item.id}`,
    },
    body: JSON.stringify({
      aps: {
        alert: { title: item.title, body: item.body },
        sound: "default",
        "thread-id": item.group_ride_id ? `group-ride-${item.group_ride_id}` : "group-rides",
      },
      deep_link: item.deep_link,
      share_token: shareToken,
    }),
  });
};

Deno.serve(async request => {
  try {
    const workerSecret = required("PUSH_WORKER_SECRET");
    if (request.headers.get("x-worker-secret") !== workerSecret) {
      return new Response("Unauthorized", { status: 401 });
    }

    await rest("rpc/enqueue_due_group_ride_reminders", {
      method: "POST",
      body: "{}",
    });

    const response = await rest(
      "notification_outbox?select=id,recipient_id,group_ride_id,kind,title,body,deep_link,attempts" +
        "&status=in.(pending,failed)&scheduled_for=lte.now()&attempts=lt.5&order=scheduled_for.asc&limit=25",
    );
    if (!response.ok) throw new Error(`Outbox query failed: ${await response.text()}`);
    const items = await response.json() as OutboxItem[];
    if (!items.length) return Response.json({ delivered: 0, failed: 0, skipped: 0 });

    const jwt = await makeAPNsJWT();
    let delivered = 0;
    let failed = 0;
    let skipped = 0;
    let deferred = 0;

    for (const item of items) {
      await patchOutbox(item.id, { status: "sending", attempts: item.attempts + 1 });

      if (
        item.kind === "group_rsvp" ||
        item.kind === "group_updated" ||
        item.kind === "group_announcement"
      ) {
        const preferenceResponse = await rest(
          `notification_preferences?select=quiet_hours,timezone&user_id=eq.${item.recipient_id}&limit=1`,
        );
        const preferences = preferenceResponse.ok
          ? await preferenceResponse.json() as Preferences[]
          : [];
        const preference = preferences[0];
        if (preference?.quiet_hours && isQuietTime(preference.timezone)) {
          await patchOutbox(item.id, {
            status: "pending",
            scheduled_for: new Date(Date.now() + 60 * 60 * 1_000).toISOString(),
          });
          deferred += 1;
          continue;
        }
      }

      const deviceResponse = await rest(
        `push_devices?select=id,token,environment&user_id=eq.${item.recipient_id}&is_active=eq.true`,
      );
      const devices = deviceResponse.ok ? await deviceResponse.json() as PushDevice[] : [];
      if (!devices.length) {
        await patchOutbox(item.id, { status: "skipped", last_error: "No active APNs device" });
        skipped += 1;
        continue;
      }

      let successes = 0;
      const errors: string[] = [];
      for (const device of devices) {
        const push = await sendToDevice(item, device, jwt);
        if (push.ok) {
          successes += 1;
          continue;
        }
        const reason = await push.text();
        errors.push(`${push.status}: ${reason}`);
        if (push.status === 410 || reason.includes("BadDeviceToken") || reason.includes("Unregistered")) {
          await rest(`push_devices?id=eq.${device.id}`, {
            method: "PATCH",
            body: JSON.stringify({ is_active: false, updated_at: new Date().toISOString() }),
          });
        }
      }

      if (successes > 0) {
        await patchOutbox(item.id, {
          status: "sent",
          sent_at: new Date().toISOString(),
          last_error: errors.length ? errors.join("; ").slice(0, 1_000) : null,
        });
        delivered += 1;
      } else {
        await patchOutbox(item.id, {
          status: "failed",
          last_error: errors.join("; ").slice(0, 1_000) || "APNs delivery failed",
        });
        failed += 1;
      }
    }

    return Response.json({ delivered, failed, skipped, deferred });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Notification worker failed";
    return Response.json({ error: message }, { status: 503 });
  }
});
