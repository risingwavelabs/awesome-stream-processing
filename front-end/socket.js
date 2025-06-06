const { Kafka } = require('kafkajs');
const WebSocket = require('ws');

const kafka = new Kafka({ brokers: ['localhost:9092'] });
const consumer = kafka.consumer({ groupId: 'data-display' });
const wss = new WebSocket.Server({ port: 5001 });

(async () => {
    await consumer.connect();
    await consumer.subscribe({ topic: 'data-display', fromBeginning: false });
    consumer.run({
        eachMessage: async ({ message }) => {
            const msg = message.value.toString();
            wss.clients.forEach(ws => {
                if (ws.readyState === ws.OPEN) ws.send(msg);
            });
        }
    });
})();
