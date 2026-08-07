from app.domains.reports.providers import (
    GeneratedImage,
    GeneratorResult,
    WebQuery,
    WebSource,
)


class FakePlannerProvider:
    def __init__(self, result) -> None:
        self.result = result
        self.calls = 0
        self.requests = []

    async def plan(self, request):
        self.calls += 1
        self.requests.append(request)
        return self.result


class FakeGeneratorProvider:
    def __init__(self, result: GeneratorResult) -> None:
        self.result = result
        self.calls = 0
        self.requests = []

    async def generate(self, request):
        self.calls += 1
        self.requests.append(request)
        return self.result


class FakeWebSearchProvider:
    def __init__(self, sources: list[WebSource] | None = None) -> None:
        self.sources = sources or []
        self.calls = 0
        self.queries = []

    async def search(self, queries: list[WebQuery]) -> list[WebSource]:
        self.calls += 1
        self.queries.append(queries)
        return self.sources


class FakeIllustrationProvider:
    def __init__(self, image: GeneratedImage) -> None:
        self.image = image
        self.calls = 0
        self.prompts = []

    async def generate(self, prompt: str) -> GeneratedImage:
        self.calls += 1
        self.prompts.append(prompt)
        return self.image
