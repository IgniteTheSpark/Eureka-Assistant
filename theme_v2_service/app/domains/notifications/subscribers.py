import asyncio
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from typing import Any


NotificationFrame = dict[str, Any]


@dataclass(frozen=True, eq=False)
class SubscriberFrame(Mapping[str, Any]):
    event: str
    payload: NotificationFrame

    def __getitem__(self, key: str) -> Any:
        return self.payload[key]

    def __iter__(self) -> Iterator[str]:
        return iter(self.payload)

    def __len__(self) -> int:
        return len(self.payload)

    def __eq__(self, other: object) -> bool:
        if isinstance(other, SubscriberFrame):
            return self.event == other.event and self.payload == other.payload
        if isinstance(other, Mapping):
            return self.payload == dict(other)
        return False


SubscriberQueue = asyncio.Queue[SubscriberFrame]


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

    def publish(
        self,
        user_id: str,
        frame: SubscriberFrame | NotificationFrame,
    ) -> int:
        normalized = (
            frame
            if isinstance(frame, SubscriberFrame)
            else SubscriberFrame(event="notification", payload=frame)
        )
        dropped = 0
        for queue in tuple(self._subscribers.get(user_id, ())):
            try:
                queue.put_nowait(normalized)
            except asyncio.QueueFull:
                dropped += 1
        return dropped
