/// UI models for the chat, mirroring the web `useChat` shapes. Agent messages
/// hold an ordered list of [ChatPart]s so streamed text / tool calls / results
/// interleave in arrival order.
sealed class ChatPart {
  const ChatPart();
}

class TextPart extends ChatPart {
  final String text;
  const TextPart(this.text);
}

class ToolCallPart extends ChatPart {
  final String name;
  const ToolCallPart(this.name);
}

class ToolResultPart extends ChatPart {
  final String name;
  final Map<String, dynamic> response;
  const ToolResultPart(this.name, this.response);
}

class ErrorPart extends ChatPart {
  final String message;
  const ErrorPart(this.message);
}

/// Persisted created cards replayed from history (a message's `cards` field).
class CardsPart extends ChatPart {
  final List<Map<String, dynamic>> cards;
  const CardsPart(this.cards);
}

enum AgentWorkPhase { understanding, executing, composing, organizing }

/// A chat session entry for the sidebar.
class SessionInfo {
  final String id;
  final String title;
  final DateTime createdAt;
  const SessionInfo(this.id, this.title, this.createdAt);
}

class ChatMessage {
  final String id;
  final bool isUser;

  /// Stable provenance id shared by the user input and assets created from it.
  String? inputTurnId;

  /// User text (user messages) or the concatenated agent text (convenience).
  String text;

  /// Ordered parts (agent messages only).
  final List<ChatPart> parts;

  bool streaming;
  AgentWorkPhase workPhase;
  DateTime? processingStartedAt;
  int? elapsedMs;
  int? tokens;

  ChatMessage.user(this.id, this.text, {this.inputTurnId})
    : isUser = true,
      parts = const [],
      streaming = false,
      workPhase = AgentWorkPhase.understanding;

  ChatMessage.agent(
    this.id, {
    this.inputTurnId,
    this.workPhase = AgentWorkPhase.understanding,
  }) : isUser = false,
       text = '',
       parts = <ChatPart>[],
       streaming = true;

  void advanceWorkPhase(AgentWorkPhase next) {
    if (_workPhaseRank(next) >= _workPhaseRank(workPhase)) workPhase = next;
  }
}

int _workPhaseRank(AgentWorkPhase phase) => switch (phase) {
  AgentWorkPhase.understanding => 0,
  AgentWorkPhase.executing => 1,
  AgentWorkPhase.composing => 2,
  AgentWorkPhase.organizing => 3,
};
