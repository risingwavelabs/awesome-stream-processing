import { Kafka } from "kafkajs";

const CFG = {
    // Kafka
    KAFKA_BROKERS: ["127.0.0.1:9092"],
    TOPIC_GPS: "gps_stream",
    TOPIC_TRAFFIC: "traffic_stream",
    TOPIC_ORDERS: "order_stream",

    // Grid size
    GRID: 0.002,

    // Demo bounding box
    LAT_MIN: 1.285,
    LAT_MAX: 1.330,
    LON_MIN: 103.830,
    LON_MAX: 103.880,

    VEHICLES: 18,
    ORDER_CREATE_EVERY_SEC: 12,
    MAX_ACTIVE_ORDERS: 60,

    // Intervals
    GPS_TICK_MS: 1000,
    TRAFFIC_TICK_MS: 8000,
    ORDER_TICK_MS: 2000,

    // Speeds
    VEHICLE_SPEED_BASE: 38,
    VEHICLE_SPEED_JITTER: 8,

    // Congestion factor
    CONGESTION_FACTOR: 0.6,

    // Order timing
    PICKUP_AFTER_SEC: 8,
    IN_TRANSIT_AFTER_SEC: 20,
    DELIVER_AFTER_SEC_MIN: 70,
    DELIVER_AFTER_SEC_MAX: 160
};

function isoNow() { return new Date().toISOString(); }

// Grid helpers
function gridId(lat, lon) {
    const gi = Math.floor(lat / CFG.GRID);
    const gj = Math.floor(lon / CFG.GRID);
    return `${gi}_${gj}`;
}
function gridBBoxFromId(gid) {
    const [gi, gj] = gid.split("_").map(Number);
    const min_lat = gi * CFG.GRID;
    const min_lon = gj * CFG.GRID;
    const max_lat = min_lat + CFG.GRID;
    const max_lon = min_lon + CFG.GRID;
    return { min_lat, min_lon, max_lat, max_lon };
}
function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

function rand(a, b) { return a + Math.random() * (b - a); }
function randint(a, b) { return Math.floor(rand(a, b + 1)); }

// Haversine distance
function haversineKm(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const toRad = x => x * Math.PI / 180;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const A =
        Math.sin(dLat/2)**2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon/2)**2;
    return 2 * R * Math.asin(Math.sqrt(A));
}

const kafka = new Kafka({ clientId: "sc-simulator", brokers: CFG.KAFKA_BROKERS });
const producer = kafka.producer({ allowAutoTopicCreation: true });

async function send(topic, payload) {
    try {
        await producer.send({
            topic,
            messages: [{ value: JSON.stringify(payload) }]
        });
        return true;
    } catch (e) {
        console.error(`[KAFKA ERR] ${topic} ${e?.name || "Error"}: ${e?.message || e}`);
        return false;
    }
}

async function emit(table, payload) {
    if (table === "gps_raw") return send(CFG.TOPIC_GPS, payload);
    if (table === "traffic_raw") return send(CFG.TOPIC_TRAFFIC, payload);
    if (table === "order_updates_raw") return send(CFG.TOPIC_ORDERS, payload);
    throw new Error(`Unknown table/topic mapping: ${table}`);
}

// Traffic regions
function buildRegionGrid() {
    const regions = [];
    const giMin = Math.floor(CFG.LAT_MIN / CFG.GRID);
    const giMax = Math.floor(CFG.LAT_MAX / CFG.GRID);
    const gjMin = Math.floor(CFG.LON_MIN / CFG.GRID);
    const gjMax = Math.floor(CFG.LON_MAX / CFG.GRID);

    let k = 1;
    for (let gi = giMin; gi <= giMax; gi++) {
        for (let gj = gjMin; gj <= gjMax; gj++) {
            const gid = `${gi}_${gj}`;
            const bbox = gridBBoxFromId(gid);
            regions.push({
                region_id: `R${k++}`,
                grid_id: gid,
                ...bbox
            });
        }
    }
    return regions;
}

const REGIONS = buildRegionGrid();

// Fixed depots
const DEPOTS = [
    { name: "Depot-A", lat: 1.300, lon: 103.840 },
    { name: "Depot-B", lat: 1.312, lon: 103.865 },
    { name: "Depot-C", lat: 1.292, lon: 103.872 }
];

function randomDestination() {
    return {
        lat: rand(CFG.LAT_MIN + 0.004, CFG.LAT_MAX - 0.004),
        lon: rand(CFG.LON_MIN + 0.004, CFG.LON_MAX - 0.004)
    };
}

// Vehicles and routes
const vehicles = Array.from({ length: CFG.VEHICLES }, (_, i) => {
    const depot = DEPOTS[i % DEPOTS.length];
    const dest = randomDestination();
    return {
        id: `V${String(i + 1).padStart(2, "0")}`,
        lat: depot.lat + rand(-0.001, 0.001),
        lon: depot.lon + rand(-0.001, 0.001),
        baseSpeed: CFG.VEHICLE_SPEED_BASE + rand(-CFG.VEHICLE_SPEED_JITTER, CFG.VEHICLE_SPEED_JITTER),
        route: [depot, dest, depot],
        wp: 1
    };
});

// Orders state
let orderSeq = 1;
const orders = new Map(); // order_id -> state

function newOrderForVehicle(v) {
    const order_id = `O${String(orderSeq++).padStart(5, "0")}`;
    const dest = randomDestination();

    const createdAt = Date.now();
    const pickupAt = createdAt + CFG.PICKUP_AFTER_SEC * 1000;
    const inTransitAt = createdAt + CFG.IN_TRANSIT_AFTER_SEC * 1000;

    // Promised time
    const dist = haversineKm(v.lat, v.lon, dest.lat, dest.lon);
    const nominalSpeed = 28;
    const travelMin = (dist / nominalSpeed) * 60;
    const bufferMin = 8 + Math.random() * 18;
    const promisedTs = new Date(createdAt + (travelMin + bufferMin) * 60 * 1000);

    const deliverAfter = randint(CFG.DELIVER_AFTER_SEC_MIN, CFG.DELIVER_AFTER_SEC_MAX) * 1000;
    const deliverAt = createdAt + deliverAfter;

    const o = {
        order_id,
        vehicle_id: v.id,
        dest_lat: dest.lat,
        dest_lon: dest.lon,
        promised_ts: promisedTs.toISOString(),
        createdAt, pickupAt, inTransitAt, deliverAt,
        status: "created",
        lastEmit: 0
    };
    orders.set(order_id, o);
    return o;
}

async function emitOrderUpdate(o, status) {
    o.status = status;
    const payload = {
        order_id: o.order_id,
        vehicle_id: o.vehicle_id,
        dest_lat: o.dest_lat,
        dest_lon: o.dest_lon,
        promised_ts: o.promised_ts,
        status,
        updated_at: isoNow()
    };
    await emit("order_updates_raw", payload);
}

// Traffic model
let incident = {
    active: false,
    grid_id: null,
    until: 0
};

function baseCongestionAtTime(t) {
    const x = t / 60000;
    const wave = 0.45 + 0.25 * Math.sin(x / 2);
    return clamp(wave, 0.05, 0.85);
}

function congestionForRegion(region, t) {
    let c = baseCongestionAtTime(t);

    const h = region.grid_id.split("_").reduce((a, b) => a + Number(b), 0);
    c += ((h % 7) - 3) * 0.02;

    c += (Math.random() - 0.5) * 0.06;

    if (incident.active && incident.grid_id === region.grid_id) {
        c = Math.max(c, 0.92);
    }

    return clamp(c, 0.02, 0.98);
}

function trafficSpeedFromCongestion(c) {
    return clamp(55 - c * 45, 10, 60);
}

// Async pool with limited concurrency
async function asyncPool(limit, items, fn) {
    const ret = [];
    const executing = [];
    for (const item of items) {
        const p = Promise.resolve().then(() => fn(item));
        ret.push(p);
        if (limit <= items.length) {
            const e = p.then(() => executing.splice(executing.indexOf(e), 1));
            executing.push(e);
            if (executing.length >= limit) {
                await Promise.race(executing);
            }
        }
    }
    return Promise.all(ret);
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function tickTraffic() {
    const ts = isoNow();
    const now = Date.now();

    if (!incident.active && Math.random() < 0.18) {
        const r = REGIONS[randint(0, REGIONS.length - 1)];
        incident = {
            active: true,
            grid_id: r.grid_id,
            until: now + randint(30, 80) * 1000
        };
        console.log("[INCIDENT] start at grid", incident.grid_id);
    }
    if (incident.active && now > incident.until) {
        console.log("[INCIDENT] end at grid", incident.grid_id);
        incident.active = false;
        incident.grid_id = null;
    }

    let ok = 0;
    let fail = 0;

    const CONCURRENCY = 40;
    await asyncPool(CONCURRENCY, REGIONS, async (r) => {
        const c = congestionForRegion(r, now);
        const s = trafficSpeedFromCongestion(c);
        const success = await emit("traffic_raw", {
            event_ts: ts,
            region_id: r.region_id,
            min_lat: r.min_lat,
            min_lon: r.min_lon,
            max_lat: r.max_lat,
            max_lon: r.max_lon,
            congestion: c,
            traffic_speed_kmh: s
        });
        if (success) ok++; else fail++;

        const sent = ok + fail;
        if (sent % 80 === 0) {
            console.log(`[TRAFFIC] sent ${sent}/${REGIONS.length} (ok=${ok}, fail=${fail})`);
        }

        if (sent % 120 === 0) await sleep(10);
    });

    console.log(`[TRAFFIC] tick done (ok=${ok}, fail=${fail})`);
}

// Vehicle movement
function moveVehicle(v, congestion) {
    const target = v.route[v.wp];
    const dx = target.lat - v.lat;
    const dy = target.lon - v.lon;
    const dist = Math.sqrt(dx*dx + dy*dy);

    if (dist < 0.001) {
        v.wp = (v.wp + 1) % v.route.length;
        return;
    }

    // Apply congestion impact
    const effSpeed = Math.max(6, v.baseSpeed * (1 - congestion * CFG.CONGESTION_FACTOR));
    const kmPerSec = effSpeed / 3600;
    const stepKm = kmPerSec * (CFG.GPS_TICK_MS / 1000);

    const dLat = stepKm / 110.574;
    const dLon = stepKm / (111.320 * Math.cos(v.lat * Math.PI / 180));

    const ux = dx / dist;
    const uy = dy / dist;

    v.lat += ux * dLat;
    v.lon += uy * dLon;

    v.lat = clamp(v.lat, CFG.LAT_MIN, CFG.LAT_MAX);
    v.lon = clamp(v.lon, CFG.LON_MIN, CFG.LON_MAX);

    return { effSpeed };
}

function regionCongestionLookup(lat, lon) {
    const gid = gridId(lat, lon);
    if (incident.active && incident.grid_id === gid) return 0.95;

    let c = baseCongestionAtTime(Date.now());
    const h = gid.split("_").reduce((a, b) => a + Number(b), 0);
    c += ((h % 7) - 3) * 0.02;
    return clamp(c, 0.05, 0.9);
}

async function tickGPS() {
    const ts = isoNow();
    for (const v of vehicles) {
        const c = regionCongestionLookup(v.lat, v.lon);
        const moved = moveVehicle(v, c);
        const speed = moved?.effSpeed ?? v.baseSpeed;

        await emit("gps_raw", {
            event_ts: ts,
            vehicle_id: v.id,
            lat: v.lat,
            lon: v.lon,
            speed_kmh: speed
        });
    }
}

async function tickOrders() {
    const now = Date.now();

    const activeCount = [...orders.values()].filter(o => o.status !== "delivered").length;
    if (activeCount < CFG.MAX_ACTIVE_ORDERS && (now / 1000) % CFG.ORDER_CREATE_EVERY_SEC < (CFG.ORDER_TICK_MS / 1000)) {
        const n = Math.random() < 0.35 ? 2 : 1;
        for (let i = 0; i < n; i++) {
            const v = vehicles[randint(0, vehicles.length - 1)];
            const o = newOrderForVehicle(v);
            await emit("order_updates_raw", o);
            await emitOrderUpdate(o, "created");
        }
    }

    for (const o of orders.values()) {
        if (o.status === "delivered") continue;

        let next = o.status;
        if (now >= o.deliverAt) next = "delivered";
        else if (now >= o.inTransitAt) next = "in_transit";
        else if (now >= o.pickupAt) next = "picked_up";

        if (next !== o.status) {
            await emitOrderUpdate(o, next);
        } else {
            if (Math.random() < 0.03 && now - o.lastEmit > 15000) {
                o.lastEmit = now;
                await emitOrderUpdate(o, o.status);
            }
        }
    }
}

// Initial data
async function warmStart() {
    console.log("Warming up traffic grid:", REGIONS.length, "cells");
    tickTraffic().catch(e => console.error("[TRAFFIC] warmup failed", e));

    console.log("Seeding initial orders...");
    for (let i = 0; i < Math.min(25, CFG.MAX_ACTIVE_ORDERS); i++) {
        const v = vehicles[i % vehicles.length];
        const o = newOrderForVehicle(v);
        await emitOrderUpdate(o, "created");
    }
    for (const o of [...orders.values()].slice(0, 10)) {
        await emitOrderUpdate(o, "picked_up");
        await emitOrderUpdate(o, "in_transit");
    }
}

console.log("Simulator starting...");
await producer.connect();
await warmStart();

const t1 = setInterval(tickGPS, CFG.GPS_TICK_MS);
const t2 = setInterval(tickTraffic, CFG.TRAFFIC_TICK_MS);
const t3 = setInterval(tickOrders, CFG.ORDER_TICK_MS);

console.log("Running. GPS:", CFG.GPS_TICK_MS, "ms; Traffic:", CFG.TRAFFIC_TICK_MS, "ms; Orders:", CFG.ORDER_TICK_MS, "ms");
console.log("Kafka brokers:", CFG.KAFKA_BROKERS.join(","));

async function shutdown() {
    clearInterval(t1);
    clearInterval(t2);
    clearInterval(t3);
    try { await producer.disconnect(); } catch {}
    process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
