const {parentPort, workerData} = require('worker_threads');
const {Connection, SystemProgram, PublicKey} = require('@solana/web3.js');

const rpcClient = new Connection(workerData.rpcNodeUrl, 'confirmed');
const SPL_TOKEN_PROGRAM_ID = new PublicKey(workerData.splTokenProgramId);

const getBlock = async (slot, retries = 3, delay = 1500) => {
    for (let i = 0; i < retries; i++) {
        try {
            return await rpcClient.getBlock(slot, {
                maxSupportedTransactionVersion: 0,
                commitment: "confirmed",
                transactionDetails: "full"
            });
        } catch (error) {
            if (i < retries - 1) {
                await new Promise(r => setTimeout(r, delay));
            } else {
                console.error(`Failed to fetch block ${slot}:`, error.message);
                return [];
            }
        }
    }
}

const pauseTransactionsBatch = (transactions, slot, blockTime)  => {
    const txs = [];

    for (const {transaction: tx, meta} of transactions) {
        const message = tx.message;
        let keys = message.staticAccountKeys.slice();

        if (message.addressTableLookups && meta.loadedAddresses) {
            const {writable, readonly} = meta.loadedAddresses;
            keys.push(...writable, ...readonly);
        }

        for (const instr of message.compiledInstructions) {
            const programId = keys[instr.programIdIndex];

            if (programId.equals(SystemProgram.programId) && instr.data[0] === 2) {
                txs.push({
                    slot: slot,
                    tx_type: "SOL Transfer",
                    blockTime: new Date(blockTime * 1000).toISOString(),
                    signature: tx.signatures[0],
                    sender: keys[instr.accountKeyIndexes[0]].toBase58(),
                    receiver: keys[instr.accountKeyIndexes[1]].toBase58(),
                    amount: Number(instr.data.readBigUInt64LE(4)),
                    fee: meta.fee
                });
            }

            if (programId.equals(SPL_TOKEN_PROGRAM_ID) && instr.data[0] === 3) {
                txs.push({
                    slot: slot,
                    tx_type: "SPL-Token Transfer",
                    blockTime: new Date(blockTime * 1000).toISOString(),
                    signature: tx.signatures[0],
                    sender: keys[instr.accountKeyIndexes[0]].toBase58(),
                    receiver: keys[instr.accountKeyIndexes[1]].toBase58(),
                    amount: Number(instr.data.readBigUInt64LE(1)),
                    fee: meta.fee
                });
            }
        }
    }

    return txs;
}

parentPort.on('message', async slot => {
    try {
        const block = await getBlock(slot);
        if (!block || !block.transactions) return parentPort.postMessage([]);

        const txs = pauseTransactionsBatch(block.transactions, slot, block.blockTime);

        parentPort.postMessage(txs);
    } catch (err) {
        console.error(`Worker failed slot ${slot}:`, err.message);
        parentPort.postMessage([]);
    }
});
