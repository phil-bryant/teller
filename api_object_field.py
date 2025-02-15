from typing import Optional, Any, Annotated

class APIObjectField:
    def __init__(self, name: str, api_name: Optional[str] = None, value: Any = None, annotated: Annotated = None):
        self.name = name
        self.api_name = api_name
        self.value = value
        self.annotated = annotated 