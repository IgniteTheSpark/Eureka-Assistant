import asyncio
from typing import Any


NotificationFrame = dict[str, Any]
SubscriberQueue = asyncio.Queue[NotificationFrame]


class SubscriberRegistry:
    def __init__(self, queue_size: int = 100):
        if queue_size < 1:
            raise ValueError("queue_size must be positive")
        self._queue_size = queue_size
        self._subscribers: dict[str, set[SubscriberQueue]] = {}

    def subscribe(self, user_id: str) -> SubscriberQueue:
        queue: SubscriberQueue = asyncio.Queue(maxsize=self._queue_size)
        self._subscribers.setdefault(user_id, set()).add(queue)
        return queue

    def unsubscribe(self, user_id: str, queue: SubscriberQueue) -> None:
        subscribers = self._subscribers.get(user_id)
        if subscribers is None:
            return
        subscribers.discard(queue)
        if not subscribers:
            self._subscribers.pop(user_id, None)

    def publish(self, user_id: str, payload: NotificationFrame) -> int:
        dropped = 0
        for queue in tuple(self._subscribers.get(user_id, ())):
            try:
                queue.put_nowait(payload)
            except asyncio.QueueFull:
                dropped += 1
        return dropped
