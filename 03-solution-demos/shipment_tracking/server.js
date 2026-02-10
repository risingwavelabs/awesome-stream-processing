import http from "node:http";
import {URL} from "node:url";
import pg from "pg";

const {Pool} = pg;

const CFG = {
    HOST: "127.0.0.1",
    PORT: Number(process.env.PORT || 8787),

    RW_HOST: process.env.RW_HOST || "127.0.0.1",
    RW_PORT: Number(process.env.RW_PORT || 4566),
    RW_DB: process.env.RW_DB || "dev",
    RW_USER: process.env.RW_USER || "root",
    RW_PASSWORD: process.env.RW_PASSWORD || "",

    MAX_ROWS: 200,
};

const pool = new Pool({
    host: CFG.RW_HOST,
    port: CFG.RW_PORT,
    user: CFG.RW_USER,
    password: CFG.RW_PASSWORD,
    database: CFG.RW_DB,
    max: 5,
});

function applyCors(res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET,OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "content-type");
    res.setHeader("Access-Control-Max-Age", "86400");
    res.setHeader("X-Demo-Server", "rw-api");
}

function sendJson(res, code, obj) {
    applyCors(res);
    res.writeHead(code, {
        "Content-Type": "application/json; charset=utf-8",
    });
    res.end(JSON.stringify(obj));
}

async function querySnapshot(maxRows) {
    const client = await pool.connect();
    try {
        const limit = Math.max(1, Math.min(1000, Number(maxRows) || CFG.MAX_ROWS));

        const rowsSql = `
            SELECT order_id,
                   vehicle_id,
                   status,
                   vehicle_lat,
                   vehicle_lon,
                   dest_lat,
                   dest_lon,
                   gps_ts,
                   eta_ts,
                   promised_ts,
                   eta_minutes,
                   delay_interval,
                   congestion,
                   traffic_speed_kmh,
                   vehicle_speed_kmh
            FROM sc.order_eta_live
            WHERE status IN ('in_transit','delayed')
            ORDER BY delay_interval DESC NULLS LAST
                LIMIT ${limit}
        `;

        const kpiSql = `
            WITH in_transit AS (SELECT *
                                FROM sc.order_eta_live
                                WHERE status = 'in_transit')
            SELECT count(*)::bigint AS in_transit, count(*) FILTER (WHERE delay_interval > interval '0')::bigint AS delayed_in_transit, avg(eta_minutes) AS avg_eta_minutes
            FROM in_transit
        `;

        const [rowsRes, kpiRes] = await Promise.all([
            client.query(rowsSql),
            client.query(kpiSql),
        ]);

        const k = kpiRes.rows[0] || {};

        return {
            ts: new Date().toISOString(),
            kpis: {
                in_transit: Number(k.in_transit || 0),
                delayed: Number(k.delayed_in_transit || 0),
                avg_eta_minutes: k.avg_eta_minutes == null ? null : Number(k.avg_eta_minutes),
            },
            rows: rowsRes.rows,
        };
    } finally {
        client.release();
    }
}

async function queryOrder(orderId) {
    const client = await pool.connect();
    try {
        const sql = `
            SELECT order_id,
                   vehicle_id,
                   status,
                   vehicle_lat,
                   vehicle_lon,
                   dest_lat,
                   dest_lon,
                   gps_ts,
                   eta_ts,
                   promised_ts,
                   eta_minutes,
                   delay_interval,
                   congestion,
                   traffic_speed_kmh,
                   vehicle_speed_kmh
            FROM sc.order_eta_live
            WHERE order_id = $1 LIMIT 1
        `;
        const r = await client.query(sql, [orderId]);
        return r.rows[0] || null;
    } finally {
        client.release();
    }
}

const server = http.createServer(async (req, res) => {
    applyCors(res);

    if (req.method === "OPTIONS") {
        res.writeHead(204);
        res.end();
        return;
    }

    const u = new URL(req.url, `http://${req.headers.host}`);

    try {
        if (u.pathname === "/health") {
            sendJson(res, 200, {ok: true});
            return;
        }

        if (u.pathname === "/api/snapshot") {
            const maxRows = Number(u.searchParams.get("max_rows") || CFG.MAX_ROWS);
            const snap = await querySnapshot(maxRows);
            sendJson(res, 200, snap);
            return;
        }

        if (u.pathname.startsWith("/api/orders/")) {
            const orderId = decodeURIComponent(u.pathname.slice("/api/orders/".length));
            const row = await queryOrder(orderId);
            if (!row) {
                sendJson(res, 404, {error: "not found"});
                return;
            }
            sendJson(res, 200, row);
            return;
        }

        sendJson(res, 404, {error: "not found"});
    } catch (e) {
        sendJson(res, 500, {error: String(e?.message || e)});
    }
});

server.listen(CFG.PORT, CFG.HOST, () => {
    console.log(`API listening on http://${CFG.HOST}:${CFG.PORT}`);
    console.log(`GET  /api/snapshot`);
    console.log(`GET  /api/orders/:order_id`);
});

process.on("SIGINT", async () => {
    try {
        await pool.end();
    } catch {
    }
    process.exit(0);
});
