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

class ChatMessage {
  final String id;
  final bool isUser;

  /// User text (user messages) or the concatenated agent text (convenience).
  String text;

  /// Ordered parts (agent messages only).
  final List<ChatPart> parts;

  bool streaming;
  int? elapsedMs;
  int? tokens;

  ChatMessage.user(this.id, this.text)
      : isUser = true,
        parts = const [],
        streaming = false;

  ChatMessage.agent(this.id)
      : isUser = false,
        text = '',
        parts = <ChatPart>[],
        streaming = true;
}
