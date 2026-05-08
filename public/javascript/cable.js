// Minimal Action Cable client - speaks the JSON protocol over a vanilla WebSocket.
// Auto-reconnects with backoff. No build step, no dependencies.
//
// Usage:
//   const sub = subscribeChannel("SlideshowChannel", {
//     connected()    { ... },
//     disconnected() { ... },
//     received(msg)  { ... }
//   });
//
// `msg` is the broadcast payload as a plain JS object.

const CABLE_URL = (location.protocol === "https:" ? "wss://" : "ws://") +
                  location.host + "/cable";
const SUBPROTOCOL = "actioncable-v1-json";

let socket          = null;
let connected       = false;
let reconnectDelay  = 1000;
let reconnectTimer  = null;
const subscriptions = []; // { identifier, callbacks }

function connect() {
  if (socket && (socket.readyState === WebSocket.OPEN ||
                 socket.readyState === WebSocket.CONNECTING)) return;

  socket = new WebSocket(CABLE_URL, SUBPROTOCOL);

  socket.addEventListener("open", () => {
    // Send subscribe commands once Action Cable sends the welcome message.
  });

  socket.addEventListener("message", (event) => {
    let data;
    try { data = JSON.parse(event.data); } catch (e) { return; }

    switch (data.type) {
      case "welcome":
        connected = true;
        reconnectDelay = 1000;
        // (Re-)subscribe everything
        for (const sub of subscriptions) {
          socket.send(JSON.stringify({
            command: "subscribe",
            identifier: sub.identifier
          }));
        }
        break;

      case "ping":
        // Action Cable heartbeat - ignore
        break;

      case "confirm_subscription":
        for (const sub of subscriptions) {
          if (sub.identifier === data.identifier && sub.callbacks.connected) {
            sub.callbacks.connected();
          }
        }
        break;

      case "reject_subscription":
      case "disconnect":
        // Server-initiated disconnect; let onclose handle reconnect
        break;

      default:
        // A broadcast: { identifier, message }
        if (data.identifier && data.message !== undefined) {
          for (const sub of subscriptions) {
            if (sub.identifier === data.identifier && sub.callbacks.received) {
              sub.callbacks.received(data.message);
            }
          }
        }
    }
  });

  socket.addEventListener("close", () => {
    if (connected) {
      connected = false;
      for (const sub of subscriptions) {
        if (sub.callbacks.disconnected) sub.callbacks.disconnected();
      }
    }
    scheduleReconnect();
  });

  socket.addEventListener("error", () => {
    // close handler will fire next
  });
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    reconnectDelay = Math.min(reconnectDelay * 2, 15000);
    connect();
  }, reconnectDelay);
}

export function subscribeChannel(channelName, callbacks = {}) {
  const identifier = JSON.stringify({ channel: channelName });
  subscriptions.push({ identifier, callbacks });

  if (socket && socket.readyState === WebSocket.OPEN && connected) {
    socket.send(JSON.stringify({ command: "subscribe", identifier }));
  } else {
    connect();
  }

  return {
    unsubscribe() {
      const i = subscriptions.findIndex(s => s.identifier === identifier);
      if (i !== -1) subscriptions.splice(i, 1);
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ command: "unsubscribe", identifier }));
      }
    }
  };
}

// Kick off the connection eagerly so the first subscribeChannel() is fast.
connect();
