use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

use riterm_shared::{
    CommunicationManager, IODataType, Message, MessageBuilder, MessagePayload,
    QuicMessageClientHandle, SerializableEndpointAddr, TerminalAction,
};

// Import internal state management
use crate::internal_state::{StreamEventListener as InternalStreamEventListener, APP_STATE};

// Maximum number of concurrent sessions to prevent memory exhaustion
const MAX_CONCURRENT_SESSIONS: usize = 50;

// Helper function to validate session ticket format
fn is_valid_session_ticket(ticket: &str) -> bool {
    ticket.starts_with("ticket:") && ticket.len() > 20
}

// Parse ticket and extract NodeAddr
fn parse_ticket_node_addr(
    ticket: &str,
) -> Result<riterm_shared::NodeAddr, Box<dyn std::error::Error>> {
    use data_encoding::BASE32;
    use serde_json;

    let encoded = ticket
        .strip_prefix("ticket:")
        .ok_or("Invalid ticket format")?;
    let ticket_json_bytes = BASE32.decode(encoded.as_bytes())?;
    let ticket_json = String::from_utf8(ticket_json_bytes)?;
    let ticket_data: serde_json::Value = serde_json::from_str(&ticket_json)?;

    let endpoint_addr_b64 = ticket_data
        .get("endpoint_addr")
        .and_then(|v| v.as_str())
        .ok_or("Missing endpoint_addr in ticket")?;

    let serializable_addr = SerializableEndpointAddr::from_base64(endpoint_addr_b64)?;
    Ok(serializable_addr.try_to_node_addr()?)
}

pub struct RustError {
    pub code: i32,
    pub message: String,
}

impl From<anyhow::Error> for RustError {
    fn from(err: anyhow::Error) -> Self {
        RustError {
            code: -1,
            message: err.to_string(),
        }
    }
}

impl From<Box<dyn std::error::Error>> for RustError {
    fn from(err: Box<dyn std::error::Error>) -> Self {
        RustError {
            code: -1,
            message: err.to_string(),
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct TerminalSession {
    pub id: String,
    pub connection_id: String,
    pub node_id: String,
}

#[derive(Serialize, Deserialize)]
pub struct ConnectionConfig {
    pub node_address: String,
    pub session_id: String,
}

#[derive(Serialize, Deserialize)]
pub struct NetworkConfig {
    pub relay_url: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct TerminalCreateRequest {
    pub session_id: String,
    pub name: Option<String>,
    pub shell_path: Option<String>,
    pub working_dir: Option<String>,
    pub size: Option<(u16, u16)>,
}

#[derive(Serialize, Deserialize)]
pub struct TerminalStopRequest {
    pub session_id: String,
    pub terminal_id: String,
}

#[derive(Serialize, Deserialize)]
pub struct TerminalInputRequest {
    pub session_id: String,
    pub terminal_id: String,
    pub input: String,
}

#[derive(Serialize, Deserialize)]
pub struct TerminalResizeRequest {
    pub session_id: String,
    pub terminal_id: String,
    pub rows: u16,
    pub cols: u16,
}

pub struct StreamEvent {
    pub session_id: String,
    pub event_type: String,
    pub data: String,
}

// Initialize the app state
#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // Initialize tracing if needed
    tracing_subscriber::fmt::init();
}

#[frb(sync)]
pub fn parse_session_ticket(ticket: String) -> Result<String, RustError> {
    if is_valid_session_ticket(&ticket) {
        Ok(ticket)
    } else {
        Err(RustError {
            code: -1,
            message: "Invalid session ticket format".to_string(),
        })
    }
}

pub async fn initialize_network_with_relay(relay_url: Option<String>) -> Result<String, RustError> {
    let communication_manager = Arc::new(CommunicationManager::new("riterm_app".to_string()));
    communication_manager
        .initialize()
        .await
        .map_err(|e| RustError {
            code: -1,
            message: format!("Failed to initialize communication manager: {}", e),
        })?;

    let app_data_dir = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    let secret_key_path = app_data_dir.join("riterm_app_secret_key");

    let quic_client = QuicMessageClientHandle::new_with_secret_key(
        relay_url,
        communication_manager.clone(),
        Some(&secret_key_path),
    )
    .await
    .map_err(|e| RustError {
        code: -1,
        message: format!("Failed to initialize QUIC client: {}", e),
    })?;

    let node_id = format!("{:?}", quic_client.get_node_id().await);

    {
        let mut comm_guard = APP_STATE.communication_manager.write().await;
        *comm_guard = Some(communication_manager);
    }
    {
        let mut client_guard = APP_STATE.quic_client.write().await;
        *client_guard = Some(quic_client);
    }

    Ok(node_id)
}

pub async fn initialize_network() -> Result<String, RustError> {
    initialize_network_with_relay(None).await
}

pub async fn connect_to_peer(session_ticket: String) -> Result<String, RustError> {
    if session_ticket.trim().is_empty() {
        return Err(RustError {
            code: -1,
            message: "Session ticket cannot be empty".to_string(),
        });
    }

    if !is_valid_session_ticket(&session_ticket) {
        return Err(RustError {
            code: -1,
            message: "Invalid session ticket format".to_string(),
        });
    }

    let quic_client = {
        let client_guard = APP_STATE.quic_client.read().await;
        match client_guard.as_ref() {
            Some(c) => c.clone(),
            None => {
                return Err(RustError {
                    code: -1,
                    message: "QUIC client not initialized. Please restart the application."
                        .to_string(),
                });
            }
        }
    };

    let communication_manager = {
        let comm_guard = APP_STATE.communication_manager.read().await;
        match comm_guard.as_ref() {
            Some(cm) => cm.clone(),
            None => {
                return Err(RustError {
                    code: -1,
                    message:
                        "Communication manager not initialized. Please restart the application."
                            .to_string(),
                });
            }
        }
    };

    let node_addr = parse_ticket_node_addr(&session_ticket).map_err(|e| RustError {
        code: -1,
        message: format!("Failed to parse session ticket: {}", e),
    })?;

    let session_id = format!("session_{}", Uuid::new_v4());

    {
        let sessions = APP_STATE.sessions.read().await;
        if sessions.len() >= MAX_CONCURRENT_SESSIONS {
            return Err(RustError {
                code: -1,
                message: format!(
                    "Maximum number of sessions ({}) reached. Please disconnect some sessions first.",
                    MAX_CONCURRENT_SESSIONS
                ),
            });
        }
    }

    let (connection_id, message_receiver) = {
        let receiver = quic_client.get_message_receiver().await;
        let connection_id = quic_client
            .connect_to_server_with_node_addr(&node_addr)
            .await
            .map_err(|e| RustError {
                code: -1,
                message: format!("Failed to connect to server: {}", e),
            })?;
        (connection_id, receiver)
    };

    let terminal_session = TerminalSession {
        id: session_id.clone(),
        connection_id: connection_id.clone(),
        node_id: node_addr.node_id.to_string(),
    };

    {
        let mut sessions = APP_STATE.sessions.write().await;
        sessions.insert(session_id.clone(), terminal_session);
    }

    // Create event stream for this session
    let (sender, _receiver) = tokio::sync::mpsc::unbounded_channel::<StreamEvent>();
    let sender = Arc::new(sender);
    {
        let mut streams = APP_STATE.event_streams.write().await;
        streams.insert(session_id.clone(), sender.clone());
    }

    // Create and register event listener
    let event_listener = Arc::new(InternalStreamEventListener::new(
        session_id.clone(),
        sender.clone(),
    ));
    communication_manager
        .register_event_listener(event_listener.clone())
        .await;

    // Start message receiver task
    let session_id_clone = session_id.clone();
    let sender_clone = sender.clone();
    tokio::spawn(async move {
        let mut receiver = message_receiver;
        loop {
            match receiver.recv().await {
                Ok(message) => match &message.payload {
                    MessagePayload::Response(response) => {
                        let stream_event = StreamEvent {
                            session_id: session_id_clone.clone(),
                            event_type: "session_response".to_string(),
                            data: serde_json::json!({
                                "request_id": response.request_id,
                                "success": response.success,
                                "data": response.data,
                                "message": response.message,
                            })
                            .to_string(),
                        };
                        let _ = sender_clone.send(stream_event);
                    }
                    MessagePayload::Error(error) => {
                        let stream_event = StreamEvent {
                            session_id: session_id_clone.clone(),
                            event_type: "session_error".to_string(),
                            data: serde_json::json!({
                                "code": error.code,
                                "message": error.message,
                                "details": error.details,
                            })
                            .to_string(),
                        };
                        let _ = sender_clone.send(stream_event);
                    }
                    MessagePayload::TerminalIO(io_message) => match &io_message.data_type {
                        IODataType::Output => {
                            let stream_event = StreamEvent {
                                session_id: session_id_clone.clone(),
                                event_type: "terminal_output".to_string(),
                                data: serde_json::json!({
                                    "terminal_id": io_message.terminal_id,
                                    "data": String::from_utf8_lossy(&io_message.data),
                                })
                                .to_string(),
                            };
                            let _ = sender_clone.send(stream_event);
                        }
                        IODataType::Error => {
                            let stream_event = StreamEvent {
                                session_id: session_id_clone.clone(),
                                event_type: "terminal_error".to_string(),
                                data: serde_json::json!({
                                    "terminal_id": io_message.terminal_id,
                                    "error": String::from_utf8_lossy(&io_message.data),
                                })
                                .to_string(),
                            };
                            let _ = sender_clone.send(stream_event);
                        }
                        _ => {}
                    },
                    MessagePayload::TerminalManagement(mgmt_message) => {
                        let stream_event = StreamEvent {
                            session_id: session_id_clone.clone(),
                            event_type: "terminal_management".to_string(),
                            data: serde_json::json!({
                                "action": format!("{:?}", mgmt_message.action),
                                "request_id": mgmt_message.request_id,
                            })
                            .to_string(),
                        };
                        let _ = sender_clone.send(stream_event);
                    }
                    _ => {}
                },
                Err(_) => break,
            }
        }
    });

    Ok(session_id)
}

async fn send_message_via_client(
    connection_id: &str,
    message: Message,
    operation_name: &str,
) -> Result<(), RustError> {
    let client_guard = APP_STATE.quic_client.read().await;
    if let Some(quic_client) = client_guard.as_ref() {
        quic_client
            .send_message_to_server(connection_id, message)
            .await
            .map_err(|e| RustError {
                code: -1,
                message: format!("Failed to send {} message: {}", operation_name, e),
            })?;
        Ok(())
    } else {
        Err(RustError {
            code: -1,
            message: "QUIC client not available".to_string(),
        })
    }
}

pub async fn create_terminal(request: TerminalCreateRequest) -> Result<(), RustError> {
    let session = {
        let sessions = APP_STATE.sessions.read().await;
        sessions
            .get(&request.session_id)
            .ok_or_else(|| RustError {
                code: -1,
                message: "Session not found".to_string(),
            })?
            .clone()
    };

    let action = TerminalAction::Create {
        name: request.name,
        shell_path: request.shell_path,
        working_dir: request.working_dir,
        size: request.size.unwrap_or((24, 80)),
    };

    let message = MessageBuilder::terminal_management(
        "riterm_app".to_string(),
        action,
        Some(request.session_id.clone()),
    )
    .with_session(request.session_id.clone());

    send_message_via_client(&session.connection_id, message, "terminal creation").await
}

pub async fn stop_terminal(request: TerminalStopRequest) -> Result<(), RustError> {
    let session = {
        let sessions = APP_STATE.sessions.read().await;
        sessions
            .get(&request.session_id)
            .ok_or_else(|| RustError {
                code: -1,
                message: "Session not found".to_string(),
            })?
            .clone()
    };

    let action = TerminalAction::Stop {
        terminal_id: request.terminal_id,
    };

    let message = MessageBuilder::terminal_management(
        "riterm_app".to_string(),
        action,
        Some(request.session_id.clone()),
    )
    .with_session(request.session_id.clone());

    send_message_via_client(&session.connection_id, message, "terminal stop").await
}

pub async fn list_terminals(session_id: String) -> Result<(), RustError> {
    let session = {
        let sessions = APP_STATE.sessions.read().await;
        sessions
            .get(&session_id)
            .ok_or_else(|| RustError {
                code: -1,
                message: "Session not found".to_string(),
            })?
            .clone()
    };

    let message = MessageBuilder::terminal_management(
        "riterm_app".to_string(),
        TerminalAction::List,
        Some(session_id.clone()),
    )
    .with_session(session_id.clone());

    send_message_via_client(&session.connection_id, message, "terminal list").await
}

pub async fn send_terminal_input_to_terminal(
    request: TerminalInputRequest,
) -> Result<(), RustError> {
    let session = {
        let sessions = APP_STATE.sessions.read().await;
        sessions
            .get(&request.session_id)
            .ok_or_else(|| RustError {
                code: -1,
                message: "Session not found".to_string(),
            })?
            .clone()
    };

    let message = MessageBuilder::terminal_io(
        "riterm_app".to_string(),
        request.terminal_id,
        IODataType::Input,
        request.input.as_bytes().to_vec(),
    )
    .with_session(request.session_id.clone());

    send_message_via_client(&session.connection_id, message, "terminal input").await
}

pub async fn resize_terminal(request: TerminalResizeRequest) -> Result<(), RustError> {
    let session = {
        let sessions = APP_STATE.sessions.read().await;
        sessions
            .get(&request.session_id)
            .ok_or_else(|| RustError {
                code: -1,
                message: "Session not found".to_string(),
            })?
            .clone()
    };

    let action = TerminalAction::Resize {
        terminal_id: request.terminal_id,
        rows: request.rows,
        cols: request.cols,
    };

    let message = MessageBuilder::terminal_management(
        "riterm_app".to_string(),
        action,
        Some(request.session_id.clone()),
    )
    .with_session(request.session_id.clone());

    send_message_via_client(&session.connection_id, message, "terminal resize").await
}

pub async fn disconnect_session(session_id: String) -> Result<(), RustError> {
    let session = {
        let mut sessions = APP_STATE.sessions.write().await;
        sessions.remove(&session_id)
    };

    if let Some(session) = session {
        let quic_client = {
            let client_guard = APP_STATE.quic_client.read().await;
            client_guard.as_ref().cloned()
        };

        if let Some(quic_client) = quic_client {
            if let Err(e) = quic_client
                .disconnect_from_server(&session.connection_id)
                .await
            {
                return Err(RustError {
                    code: -1,
                    message: format!("Failed to disconnect from QUIC server: {}", e),
                });
            }
        }

        // Remove event stream
        {
            let mut streams = APP_STATE.event_streams.write().await;
            streams.remove(&session_id);
        }
    }

    Ok(())
}

pub async fn get_active_sessions() -> Result<Vec<String>, RustError> {
    let sessions = APP_STATE.sessions.read().await;
    Ok(sessions.keys().cloned().collect())
}

pub async fn get_node_info() -> Result<String, RustError> {
    let quic_client = {
        let client_guard = APP_STATE.quic_client.read().await;
        match client_guard.as_ref() {
            Some(c) => c.clone(),
            None => {
                return Err(RustError {
                    code: -1,
                    message: "QUIC client not initialized".to_string(),
                });
            }
        }
    };
    Ok(format!("{:?}", quic_client.get_node_id().await))
}

// Event streaming functionality for Flutter
pub async fn get_event_stream(session_id: String) -> Result<StreamEvent, RustError> {
    let streams = APP_STATE.event_streams.read().await;
    if let Some(_sender) = streams.get(&session_id) {
        // This is a simplified implementation
        // In a real implementation, you'd need a proper async channel to Dart
        Err(RustError {
            code: -1,
            message: "Event streaming not implemented in this simplified version".to_string(),
        })
    } else {
        Err(RustError {
            code: -1,
            message: "Session not found".to_string(),
        })
    }
}
