// Message type definitions
interface BaseMessage {
    type: string;
}

interface JoinMessage extends BaseMessage {
    type: "join";
    username: string;
}

interface AuthMessage extends BaseMessage {
    type: "authenticate";
    gameUsername?: string;
}

interface ChatMessage extends BaseMessage {
    type: "chat";
    message: string;
    username?: string;
}

interface PlayerMoveMessage extends BaseMessage {
    type: "player-move";
    position: {
        x: number;
        y: number;
    };
}

interface ReconnectMessage extends BaseMessage {
    type: "reconnect";
    token?: string;
}

type WebSocketMessage = 
    | JoinMessage
    | AuthMessage
    | ChatMessage
    | PlayerMoveMessage
    | ReconnectMessage
    | BaseMessage;

// Enhanced WebSocket service for Dhaniverse
export class WebSocketService {
    private sockets = new Map<string, WebSocket>();
    private userSockets = new Map<string, string>(); // userId -> socketId
    private socketUsers = new Map<string, string>(); // socketId -> userId
    private socketUsernames = new Map<string, string>(); // socketId -> username
    private welcomeSent = new Set<string>();
    private ipConnections = new Map<string, Set<string>>(); // IP -> socketIds
    private pendingMessages = new Map<string, Array<Record<string, unknown>>>(); // socketId -> pending messages

    constructor() {
        console.log("🔌 WebSocket service initialized");
    }

    private generateUUID(): string {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            const r = Math.random() * 16 | 0;
            const v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    handleConnection(socket: WebSocket, userId?: string, ip: string = "unknown") {
        const socketId = this.generateUUID();
        console.log(`🔗 New connection: ${socketId} from IP: ${ip}`);

        // Manage IP-based connections
        if (!this.ipConnections.has(ip)) {
            this.ipConnections.set(ip, new Set());
        }
        const ipSockets = this.ipConnections.get(ip)!;

        // Handle existing connections
        this.handleExistingConnections(ip, socketId, ipSockets);

        // Store new connection
        this.sockets.set(socketId, socket);
        ipSockets.add(socketId);

        if (userId) {
            this.associateUser(userId, socketId);
        }

        // Setup socket handlers
        this.setupSocketHandlers(socket, socketId, ip);

        // Send welcome message
        this.sendWelcomeMessage(socketId);

        return socketId;
    }

    private handleExistingConnections(ip: string, newSocketId: string, ipSockets: Set<string>) {
        if (ipSockets.size > 0) {
            console.log(`⚠️ Multiple connections from ${ip}, closing previous connections`);
            
            for (const existingSocketId of ipSockets) {
                // Skip new socket
                if (existingSocketId === newSocketId) continue;
                
                const existingSocket = this.sockets.get(existingSocketId);
                if (existingSocket?.readyState === WebSocket.OPEN) {
                    try {
                        existingSocket.send(JSON.stringify({
                            type: "connection-replaced",
                            message: "Your connection was replaced by a new one"
                        }));
                        existingSocket.close(1000, "Replaced by newer connection");
                    } catch (e) {
                        console.error("Error closing previous connection:", e);
                    }
                }
                this.cleanupSocket(existingSocketId);
            }
            ipSockets.clear();
        }
    }

    private associateUser(userId: string, socketId: string) {
        // Disconnect previous session for this user
        const existingSocketId = this.userSockets.get(userId);
        if (existingSocketId && existingSocketId !== socketId) {
            const existingSocket = this.sockets.get(existingSocketId);
            if (existingSocket?.readyState === WebSocket.OPEN) {
                existingSocket.close(1000, "Replaced by newer session");
            }
            this.cleanupSocket(existingSocketId);
        }

        this.userSockets.set(userId, socketId);
        this.socketUsers.set(socketId, userId);
        console.log(`👤 Associated user ${userId} with socket ${socketId}`);
    }

    private setupSocketHandlers(socket: WebSocket, socketId: string, ip: string) {
        socket.onopen = () => {
            console.log(`✅ WebSocket opened: ${socketId}`);
            this.sendToSocket(socketId, {
                type: "connection",
                message: "Connected to Dhaniverse server",
                socketId,
                ip
            });
            
            // Send any pending messages
            const pending = this.pendingMessages.get(socketId);
            if (pending && pending.length > 0) {
                pending.forEach(msg => this.sendToSocket(socketId, msg));
                this.pendingMessages.delete(socketId);
            }
        };

        socket.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                this.handleMessage(socketId, data);
            } catch (error) {
                console.error("❌ Error parsing message:", error);
                this.sendToSocket(socketId, {
                    type: "error",
                    message: "Invalid message format"
                });
            }
        };

        socket.onclose = () => {
            console.log(`🔌 WebSocket closed: ${socketId}`);
            this.handleDisconnect(socketId);
        };

        socket.onerror = (error) => {
            console.error(`❌ WebSocket error for ${socketId}:`, error);
            this.sendToSocket(socketId, {
                type: "error",
                message: "Connection error occurred"
            });
        };
    }

    private sendWelcomeMessage(socketId: string) {
        if (!this.welcomeSent.has(socketId)) {
            this.welcomeSent.add(socketId);
            
            // Queue welcome message if socket not open yet
            if (this.sockets.get(socketId)?.readyState !== WebSocket.OPEN) {
                this.queueMessage(socketId, {
                    type: "chat",
                    id: "system",
                    username: "System",
                    message: "Welcome to Dhaniverse! Type / to chat.",
                    timestamp: Date.now()
                });
            } else {
                setTimeout(() => {
                    this.sendToSocket(socketId, {
                        type: "chat",
                        id: "system",
                        username: "System",
                        message: "Welcome to Dhaniverse! Type / to chat.",
                        timestamp: Date.now()
                    });
                }, 1000);
            }
        }
    }

    private queueMessage(socketId: string, message: Record<string, unknown>) {
        if (!this.pendingMessages.has(socketId)) {
            this.pendingMessages.set(socketId, []);
        }
        this.pendingMessages.get(socketId)!.push(message);
    }

    private handleMessage(socketId: string, data: unknown) {
        if (!data || typeof data !== "object") {
            console.error("Invalid message format");
            return;
        }

        const message = data as WebSocketMessage;
        console.log(`📨 Message from ${socketId}:`, message.type);

        switch (message.type) {
            case "join":
                this.handleJoin(socketId, message as JoinMessage);
                break;
                
            case "authenticate":
                this.handleAuth(socketId, message as AuthMessage);
                break;
                
            case "chat":
                this.handleChat(socketId, message as ChatMessage);
                break;
                
            case "player-move":
                this.handlePlayerMove(socketId, message as PlayerMoveMessage);
                break;
                
            case "update":
                // Ignore frequent updates
                break;
                
            case "reconnect":
                this.handleReconnect(socketId, message as ReconnectMessage);
                break;
                
            default:
                console.log(`🤷 Unknown message type: ${message.type}`);
                this.sendToSocket(socketId, {
                    type: "error",
                    message: `Unknown message type: ${message.type}`
                });
        }
    }

    private handleJoin(socketId: string, data: JoinMessage) {
        if (!data.username || typeof data.username !== "string") {
            console.error("Invalid join message");
            return;
        }

        const username = data.username.trim();
        if (username.length === 0) return;

        // Check if username is already in use
        for (const [sId, existingUsername] of this.socketUsernames) {
            if (existingUsername === username && sId !== socketId) {
                this.sendToSocket(socketId, {
                    type: "error",
                    message: "Username is already taken"
                });
                return;
            }
        }

        this.socketUsernames.set(socketId, username);
        console.log(`👤 Set username ${username} for socket ${socketId}`);

        // Notify all clients
        this.broadcast({
            type: "player-joined",
            username,
            message: `${username} joined the game`
        });

        this.broadcast({
            type: "chat",
            id: "system",
            username: "System",
            message: `${username} joined the game`,
            timestamp: Date.now()
        });
    }

    private handleAuth(socketId: string, data: AuthMessage) {
        if (data.gameUsername && typeof data.gameUsername === "string") {
            this.socketUsernames.set(socketId, data.gameUsername);
            console.log(`🔑 Authenticated socket ${socketId} as ${data.gameUsername}`);
        }
    }

    private handleChat(socketId: string, data: ChatMessage) {
        const username = this.socketUsernames.get(socketId) || data.username || "Player";
        const message = data.message?.toString()?.trim() || "";
        
        if (message.length === 0) return;

        const messageId = `msg-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        
        console.log(`💬 Chat from ${username}: ${message}`);
        
        this.broadcast({
            type: "chat",
            id: messageId,
            username,
            message,
            timestamp: Date.now()
        });
    }

    private handlePlayerMove(socketId: string, data: PlayerMoveMessage) {
        const username = this.socketUsernames.get(socketId);
        if (!username) return;
        
        const position = data.position;
        if (!position || typeof position.x !== "number" || typeof position.y !== "number") {
            console.error("Invalid player position");
            return;
        }
        
        this.broadcast({
            type: "player-position",
            username,
            position
        }, socketId);
    }

    private handleReconnect(socketId: string, _data: ReconnectMessage) {
        console.log(`🔄 Reconnection request from ${socketId}`);
        const userId = this.socketUsers.get(socketId);
        
        if (userId) {
            this.associateUser(userId, socketId);
            this.sendToSocket(socketId, {
                type: "reconnect-success",
                message: "Session restored"
            });
        } else {
            this.sendToSocket(socketId, {
                type: "error",
                message: "Reconnect failed: No user session"
            });
        }
    }

    private handleDisconnect(socketId: string) {
        const username = this.socketUsernames.get(socketId);
        const userId = this.socketUsers.get(socketId);

        // Cleanup all tracking
        this.cleanupSocket(socketId);

        // Notify other players
        if (username) {
            this.broadcast({
                type: "player-left",
                username
            });

            this.broadcast({
                type: "chat",
                id: "system",
                username: "System",
                message: `${username} left the game`,
                timestamp: Date.now()
            });
        }

        // Remove user mapping
        if (userId) {
            this.userSockets.delete(userId);
            this.socketUsers.delete(socketId);
        }
    }

    private cleanupSocket(socketId: string) {
        this.sockets.delete(socketId);
        this.welcomeSent.delete(socketId);
        this.socketUsernames.delete(socketId);
        this.pendingMessages.delete(socketId);
        
        // Remove from IP tracking
        for (const [ip, sockets] of this.ipConnections) {
            if (sockets.delete(socketId)) {
                if (sockets.size === 0) {
                    this.ipConnections.delete(ip);
                }
                break;
            }
        }
    }

    sendToSocket(socketId: string, message: Record<string, unknown>) {
        const socket = this.sockets.get(socketId);
        if (!socket) return false;

        const messageStr = JSON.stringify(message);
        
        switch (socket.readyState) {
            case WebSocket.OPEN:
                try {
                    socket.send(messageStr);
                    return true;
                } catch (error) {
                    console.error(`❌ Error sending to ${socketId}:`, error);
                    return false;
                }
                
            case WebSocket.CONNECTING:
                this.queueMessage(socketId, message);
                return true;
                
            default:
                return false;
        }
    }

    broadcast(message: Record<string, unknown>, excludeSocketId?: string) {
        const messageStr = JSON.stringify(message);
        let sentCount = 0;
        let skippedCount = 0;
        let errorCount = 0;

        this.sockets.forEach((socket, socketId) => {
            if (socketId === excludeSocketId) {
                skippedCount++;
                return;
            }

            try {
                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(messageStr);
                    sentCount++;
                } else if (socket.readyState === WebSocket.CONNECTING) {
                    this.queueMessage(socketId, message);
                    sentCount++;
                } else {
                    skippedCount++;
                }
            } catch (error) {
                console.error(`Error broadcasting to ${socketId}:`, error);
                errorCount++;
            }
        });

        console.log(`📡 Broadcasted ${message.type} to ${sentCount} clients, ` +
                   `${skippedCount} skipped, ${errorCount} errors`);
    }

    sendToUser(userId: string, message: Record<string, unknown>) {
        const socketId = this.userSockets.get(userId);
        if (!socketId) {
            console.warn(`⚠️ User ${userId} not found for message:`, message.type);
            return false;
        }
        return this.sendToSocket(socketId, message);
    }

    getConnectedUsers(): string[] {
        return Array.from(this.userSockets.keys());
    }

    getConnectionCount(): number {
        return this.sockets.size;
    }

    getUsernameBySocketId(socketId: string): string | undefined {
        return this.socketUsernames.get(socketId);
    }
}

export const webSocketService = new WebSocketService();