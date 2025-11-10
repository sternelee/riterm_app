// Internal state management - not exposed to Flutter Rust Bridge

use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};

use riterm_shared::{
    CommunicationManager, Event, EventListener, EventType, Message, QuicMessageClientHandle,
};

use crate::api::iroh_client::{StreamEvent, TerminalSession};

// Global state
pub struct AppState {
    pub sessions: RwLock<HashMap<String, TerminalSession>>,
    pub communication_manager: RwLock<Option<Arc<CommunicationManager>>>,
    pub quic_client: RwLock<Option<QuicMessageClientHandle>>,
    pub event_streams: RwLock<HashMap<String, Arc<mpsc::UnboundedSender<StreamEvent>>>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            sessions: RwLock::new(HashMap::new()),
            communication_manager: RwLock::new(None),
            quic_client: RwLock::new(None),
            event_streams: RwLock::new(HashMap::new()),
        }
    }
}

lazy_static::lazy_static! {
    pub static ref APP_STATE: AppState = AppState::default();
}

/// App Event Listener that converts events to stream events
pub struct StreamEventListener {
    pub session_id: String,
    pub sender: Arc<mpsc::UnboundedSender<StreamEvent>>,
}

impl StreamEventListener {
    pub fn new(session_id: String, sender: Arc<mpsc::UnboundedSender<StreamEvent>>) -> Self {
        Self { session_id, sender }
    }
}

#[async_trait::async_trait]
impl EventListener for StreamEventListener {
    async fn handle_event(&self, event: &Event) -> anyhow::Result<()> {
        let event_type = match event.event_type {
            EventType::TerminalCreated => "terminal_created",
            EventType::TerminalStopped => "terminal_stopped",
            EventType::TerminalInput => "terminal_input",
            EventType::TerminalOutput => "terminal_output",
            EventType::TerminalError => "terminal_error",
            EventType::TcpSessionCreated => "tcp_session_created",
            EventType::TcpSessionStopped => "tcp_session_stopped",
            EventType::PeerConnected => "peer_connected",
            EventType::PeerDisconnected => "peer_disconnected",
            _ => "unknown",
        };

        let stream_event = StreamEvent {
            session_id: self.session_id.clone(),
            event_type: event_type.to_string(),
            data: serde_json::to_string(&event.data).unwrap_or_default(),
        };

        let _ = self.sender.send(stream_event);
        Ok(())
    }

    fn name(&self) -> &str {
        &self.session_id
    }

    fn supported_events(&self) -> Vec<EventType> {
        vec![
            EventType::TerminalCreated,
            EventType::TerminalStopped,
            EventType::TerminalInput,
            EventType::TerminalOutput,
            EventType::TerminalError,
            EventType::TcpSessionCreated,
            EventType::TcpSessionStopped,
            EventType::PeerConnected,
            EventType::PeerDisconnected,
        ]
    }
}

