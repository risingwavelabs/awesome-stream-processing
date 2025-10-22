import React, {useEffect, useState} from "react";
import {CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis} from "recharts";

/** --------- helpers ---------- */
const fmt = (n) => n.toLocaleString();
const toSOL = (n) => {
    let sol = Number(n);
    if (sol > 1e7) {
        return (sol / 1e9).toFixed(2);
    } else return '< 0.01';
};

function Kpi({label, value, isAmount}) {
    const display = isAmount ? `${toSOL(value)} SOL` : fmt(value);
    return (
        <div className="flex items-center justify-between py-1">
            <span className="text-sm text-gray-600 font-medium">{label}</span>
            <span className="text-sm font-semibold text-blue-600">{display}</span>
        </div>
    );
}

function Card({title, className = "", children}) {
    return (
        <div className={`bg-white border border-gray-200 rounded-2xl shadow-md p-6 ${className}`}>
            {title ? <h2 className="text-xl font-bold mb-6">{title}</h2> : null}
            {children}
        </div>
    );
}

const CustomTooltip = ({active, payload, label}) => {
    if (!active || !payload?.length) return null;
    return (
        <div className="bg-white p-2 rounded-lg border border-gray-200 shadow-lg">
            <p className="text-xs text-gray-500">{label}</p>
            <p className="text-blue-600 font-semibold">{fmt(payload[0].value)} txs</p>
        </div>
    );
};

/** --------- page ---------- */
export default function App() {
    const [twoMinStats, setTwoMinStats] = useState(null);
    const [throughputSeries, setThroughputSeries] = useState([]);
    const [recentBlocks, setRecentBlocks] = useState([]);

    useEffect(() => {
        function fetchData() {
            fetch("/api/tx-2min")
                .then((res) => res.json())
                .then(setTwoMinStats);
            fetch("/api/tx-5s")
                .then((res) => res.json())
                .then(setThroughputSeries);
            fetch("/api/blocks")
                .then((res) => res.json())
                .then(setRecentBlocks);
        }

        fetchData();
        const interval = setInterval(fetchData, 1000);
        return () => clearInterval(interval);
    }, []);

    return (
        <div className="min-h-screen bg-gray-50 text-gray-900">
            {/* header */}
            <div className="w-full px-8 py-8 space-y-6">
                <header className="flex flex-col lg:flex-row items-center justify-between gap-4">
                    <h1 className="text-4xl font-extrabold">
                        Transaction Dashboard <span className="text-blue-600">(Demo)</span>
                    </h1>
                    {/*<input
                        type="text"
                        placeholder="Search by slot or signature…"
                        className="px-4 py-2 border border-gray-300 rounded-lg w-full lg:w-96 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />*/}
                </header>

                {/* ===== About this Demo (added) ===== */}
                <Card className="space-y-4">
                    <h2 className="text-xl font-bold">About this Demo</h2>
                    <div className="grid gap-4 md:grid-cols-3">
                        <div className="bg-gray-50 rounded-xl p-4">
                            <p className="font-semibold mb-2">User Story</p>
                            <p className="text-sm leading-relaxed">
                                This demo simulates a real-time Solana explorer. We capture the latest blocks, parse both SOL and SPL-Token transfers, load them into RisingWave, and present the results on this dashboard. Users can quickly view live transaction statistics and the recent blocks.
                            </p>
                        </div>
                        <div className="bg-gray-50 rounded-xl p-4">
                            <p className="font-semibold mb-2">Why It Matters</p>
                            <p className="text-sm leading-relaxed">
                                Blockchain produces high-velocity transaction streams. This demo shows how raw chain data can be turned into real-time analytics, combining ingestion, processing, and visualization in a streamlined pipeline.
                            </p>
                        </div>
                        <div className="bg-gray-50 rounded-xl p-4">
                            <p className="font-semibold mb-2">Why RisingWave</p>
                            <ul className="list-disc list-inside text-sm space-y-1">
                                <li><span className="font-medium">Unified streaming SQL</span>: one language for real-time and historical queries.</li>
                                <li><span className="font-medium">Materialized views</span>: incremental results always fresh and query-ready.</li>
                                <li><span className="font-medium">Efficient & cost-friendly</span>: avoids re-computation, lowers system overhead.</li>
                                <li><span className="font-medium">Ecosystem compatible</span>: integrates with Kafka, PostgreSQL protocol tools.</li>
                            </ul>
                        </div>
                    </div>
                </Card>
                {/* ===== /About this Demo ===== */}

                {/* overview stats */}
                <section className="grid grid-cols-12 gap-6">
                    <Card
                        title="2-Minute Transfer Overview"
                        className="col-span-12 lg:col-span-5 flex flex-col"
                    >
                        {twoMinStats ? (
                            <div className="grid grid-cols-2 gap-6 mt-2 flex-1 items-center">
                                <div className="bg-gray-50 rounded-xl p-4">
                                    <p className="text-lg font-bold text-gray-900 mb-3">SOL Transfers</p>
                                    <Kpi label="Txs" value={twoMinStats.sol_tx_count}/>
                                    <Kpi label="Total" value={twoMinStats.sol_total_amount} isAmount/>
                                    <Kpi label="Average" value={twoMinStats.sol_avg_amount} isAmount/>
                                    <Kpi label="Max" value={twoMinStats.sol_max_amount} isAmount/>
                                    <Kpi label="Min" value={twoMinStats.sol_min_amount} isAmount/>
                                </div>
                                <div className="bg-gray-50 rounded-xl p-4">
                                    <p className="text-lg font-bold text-gray-900 mb-3">SPL-Token Transfers</p>
                                    <Kpi label="Txs" value={twoMinStats.spl_tx_count}/>
                                    <Kpi label="Total" value={twoMinStats.spl_total_amount} isAmount/>
                                    <Kpi label="Average" value={twoMinStats.spl_avg_amount} isAmount/>
                                    <Kpi label="Max" value={twoMinStats.spl_max_amount} isAmount/>
                                    <Kpi label="Min" value={twoMinStats.spl_min_amount} isAmount/>
                                </div>
                            </div>
                        ) : (
                            <div className="text-center text-gray-400 py-8">Loading…</div>
                        )}
                    </Card>

                    {/* throughput chart */}
                    <Card
                        title="5-Second Transaction Count (Last 2 Minutes)"
                        className="col-span-12 lg:col-span-7 flex flex-col"
                    >
                        <ResponsiveContainer width="100%" height="100%">
                            <LineChart data={throughputSeries} margin={{top: 16, right: 20, left: 0, bottom: 8}}>
                                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb"/>
                                <XAxis
                                    dataKey="window_start"
                                    tick={{fill: "#6b7280", fontSize: 12}}
                                    axisLine={{stroke: "#d1d5db"}}
                                />
                                <YAxis
                                    tick={{fill: "#6b7280", fontSize: 12}}
                                    axisLine={{stroke: "#d1d5db"}}
                                />
                                <Tooltip content={<CustomTooltip/>}/>
                                <Line
                                    type="monotone"
                                    dataKey="tx_count"
                                    stroke="#2563eb"
                                    strokeWidth={3}
                                    dot={{r: 4, fill: "#2563eb"}}
                                    activeDot={{r: 6, stroke: "#1d4ed8", strokeWidth: 2}}
                                />
                            </LineChart>
                        </ResponsiveContainer>
                    </Card>
                </section>

                {/* recent blocks */}
                <Card title="Recent 15 Blocks Overview">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                        {recentBlocks && recentBlocks.length > 0 ? (
                            recentBlocks.map((block) => (
                                <div
                                    key={block.slot}
                                    className="bg-white border border-gray-200 rounded-2xl shadow-md hover:shadow-lg transition p-5"
                                >
                                    <p className="text-lg font-bold mb-4">
                                        <span className="text-gray-900">Slot</span>{" "}
                                        <span className="text-blue-600">{block.slot}</span>
                                    </p>
                                    <div className="grid grid-cols-2 gap-4">
                                        <div className="bg-gray-50 rounded-lg p-3">
                                            <p className="text-base font-semibold text-gray-900 mb-2">
                                                SOL Transfers
                                            </p>
                                            <Kpi label="Txs" value={block.sol_tx_count}/>
                                            <Kpi label="Total" value={block.sol_total_amount} isAmount/>
                                            <Kpi label="Avg" value={block.sol_avg_amount} isAmount/>
                                            <Kpi label="Max" value={block.sol_max_amount} isAmount/>
                                            <Kpi label="Min" value={block.sol_min_amount} isAmount/>
                                        </div>
                                        <div className="bg-gray-50 rounded-lg p-3">
                                            <p className="text-base font-semibold text-gray-900 mb-2">
                                                SPL-Token Transfers
                                            </p>
                                            <Kpi label="Txs" value={block.spl_tx_count}/>
                                            <Kpi label="Total" value={block.spl_total_amount} isAmount/>
                                            <Kpi label="Avg" value={block.spl_avg_amount} isAmount/>
                                            <Kpi label="Max" value={block.spl_max_amount} isAmount/>
                                            <Kpi label="Min" value={block.spl_min_amount} isAmount/>
                                        </div>
                                    </div>
                                </div>
                            ))
                        ) : (
                            <div className="text-center text-gray-400 py-8 col-span-3">Loading…</div>
                        )}
                    </div>
                </Card>
            </div>
        </div>
    );
}
