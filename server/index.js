const express = require("express");
const { Pool } = require("pg");
const cors = require("cors");

const app = express();
app.use(cors());

// RisingWave connection config
const pool = new Pool({
    host: "localhost",
    port: 4566,
    user: "root",
    password: "",
    database: "dev"
});

// Set session timezone to Asia/Shanghai for all connections
pool.on("connect", (client) => {
    client.query("SET TIME ZONE 'Asia/Shanghai'");
});

// Utility function for querying RisingWave
async function query(sql, params) {
    const client = await pool.connect();
    try {
        const res = await client.query(sql, params);
        return res.rows;
    } finally {
        client.release();
    }
}

// === API Routes ===

// 1. Get the latest 15 block stats
app.get("/api/blocks", async (req, res) => {
    try {
        const rows = await query(`
      SELECT *
      FROM block_stats
      ORDER BY slot DESC
      LIMIT 15;
    `);
        res.json(rows);
    } catch (err) {
        console.error("Error fetching block stats:", err);
        res.status(500).json({ error: "Failed to fetch block stats" });
    }
});

// 2. Get the latest *complete* 2-minute window stats
app.get("/api/tx-2min", async (req, res) => {
    try {
        const rows = await query(`
      SELECT *
      FROM tx_2min_stats
      WHERE window_end < now()
      ORDER BY window_end DESC
      LIMIT 1;
    `);
        res.json(rows[0] ?? null);
    } catch (err) {
        console.error("Error fetching tx_2min stats:", err);
        res.status(500).json({ error: "Failed to fetch tx_2min stats" });
    }
});

// 3. Get the last 2 minute of 5-second TPS data
app.get("/api/tx-5s", async (req, res) => {
    try {
        const rows = await query(`
      SELECT *
      FROM tx_5s_count
      WHERE window_start >= now() - interval '2 minutes'
      ORDER BY window_start ASC;
    `);
        res.json(rows);
    } catch (err) {
        console.error("Error fetching tx_5s stats:", err);
        res.status(500).json({ error: "Failed to fetch tx_5s stats" });
    }
});

// 4. Get transactions by slot
app.get("/api/tx-by-slot/:slot", async (req, res) => {
    try {
        const { slot } = req.params;
        const rows = await query(`SELECT * FROM tx_mv WHERE slot = $1`, [slot]);
        res.json(rows);
    } catch (err) {
        console.error("Error fetching tx by slot:", err);
        res.status(500).json({ error: "Failed to fetch transactions by slot" });
    }
});

// 5. Get transaction by signature
app.get("/api/tx-by-signature/:sig", async (req, res) => {
    try {
        const { sig } = req.params;
        const rows = await query(`SELECT * FROM tx_mv WHERE signature = $1`, [sig]);
        res.json(rows);
    } catch (err) {
        console.error("Error fetching tx by signature:", err);
        res.status(500).json({ error: "Failed to fetch transaction by signature" });
    }
});

// Start server
const PORT = 3001;
app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
});
