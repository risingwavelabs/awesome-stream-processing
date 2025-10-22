const {Worker} = require('worker_threads');
require('dotenv').config();
const Kafka = require('node-rdkafka');
const {Connection} = require('@solana/web3.js');

const ENV = process.env;

const RpcNodeUrl = `https://solana-${ENV.NETWORK}.g.alchemy.com/v2/${ENV.API_KEY_ALCHEMY}`;
const WssNodeUrl = `https://wispy-tame-sky.solana-${ENV.NETWORK}.quiknode.pro/${ENV.API_KEY_QUICKNODE}/`;
const WssEndPoint = `wss://wispy-tame-sky.solana-${ENV.NETWORK}.quiknode.pro/${ENV.API_KEY_QUICKNODE}/`;
const wsConnection = new Connection(WssNodeUrl, {commitment: "confirmed", wsEndpoint: WssEndPoint});

const SplTokenProgramId = ENV.SPL_TOKEN_PROGRAM_ID;

// Kafka Producer
const producer = new Kafka.Producer({
    'metadata.broker.list': 'localhost:9092',
    'queue.buffering.max.messages': 100000,
    'queue.buffering.max.kbytes': 64 * 1024,
    'queue.buffering.max.ms': 100,
    'batch.num.messages': 10000,
    'compression.codec': 'snappy',
    'dr_cb': true
});
producer.connect();
producer.on('ready', () => console.log('Kafka producer ready'));
setInterval(() => producer.poll(), 50);

// ---------- Parse Queue (Worker Threads) ----------
const NUM_WORKERS = 16;
const workers = [];

for (let i = 0; i < NUM_WORKERS; i++) {
    const worker = new Worker('./worker.js', {
        workerData: {
            rpcNodeUrl: RpcNodeUrl,
            splTokenProgramId: SplTokenProgramId
        }
    });
    worker.setMaxListeners(100);
    workers.push(worker);
}

const parseQueue = require("async").queue(async task => {
    const {slot, workerIndex} = task;

    const worker = workers[workerIndex];

    worker.once('message', async (txs) => {
        const total = txs.length;

        producer.produce(
            "tx",
            workerIndex,
            Buffer.from(JSON.stringify({
                transactions: txs
            }))
        );

        console.log(`Block ${slot} done, send ${total} transactions messages to Risingwave`);
    });

    worker.once('error', (error) => {
        console.error(`Worker for block ${slot} error`, error.message);
    });

    worker.postMessage(slot);
}, NUM_WORKERS);

// ---------- Subscribe to Slots ----------
wsConnection.onSlotChange(slotInfo => {
    if (!slotInfo) return;

    const slot = slotInfo.slot;
    const workerIndex = slot % NUM_WORKERS;

    console.log(`Received block ${slot}`);
    parseQueue.push({slot, workerIndex});
});
